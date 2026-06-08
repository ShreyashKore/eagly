import Cocoa
import CoreMedia
import CoreVideo
import FlutterMacOS
import VideoToolbox

/// Renders a scrcpy H.264 stream into a Flutter texture using VideoToolbox.
///
/// Dart drives this in two channels:
///  - method  `flutter_scrcpy/video`        : `create` -> textureId, `dispose`
///  - binary  `flutter_scrcpy/video/feed`   : [int64 LE textureId][Annex-B bytes]
///
/// Each fed message is one access unit (config packet with SPS/PPS, or a coded
/// slice). The decoder builds a format description from the parameter sets and
/// emits CVPixelBuffers that Flutter composites directly inside the widget tree.
public class ScrcpyVideoPlugin: NSObject, FlutterPlugin {
  private let textures: FlutterTextureRegistry
  private var sessions: [Int64: ScrcpyVideoTexture] = [:]
  private let lock = NSLock()

  init(textures: FlutterTextureRegistry) {
    self.textures = textures
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ScrcpyVideoPlugin(textures: registrar.textures)

    let method = FlutterMethodChannel(
      name: "flutter_scrcpy/video", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(instance, channel: method)

    let feed = FlutterBasicMessageChannel(
      name: "flutter_scrcpy/video/feed",
      binaryMessenger: registrar.messenger,
      codec: FlutterBinaryCodec.sharedInstance())
    feed.setMessageHandler { message, reply in
      instance.handleFeed(message)
      reply(nil)
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "create":
      let texture = ScrcpyVideoTexture()
      let id = textures.register(texture)
      texture.configure(textureId: id, registry: textures)
      lock.lock()
      sessions[id] = texture
      lock.unlock()
      result(NSNumber(value: id))
    case "dispose":
      guard
        let args = call.arguments as? [String: Any],
        let id = (args["textureId"] as? NSNumber)?.int64Value
      else {
        result(FlutterError(code: "bad_args", message: "textureId required", details: nil))
        return
      }
      lock.lock()
      let texture = sessions.removeValue(forKey: id)
      lock.unlock()
      texture?.shutdown()
      textures.unregisterTexture(id)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleFeed(_ message: Any?) {
    let data: Data
    if let d = message as? Data {
      data = d
    } else if let typed = message as? FlutterStandardTypedData {
      data = typed.data
    } else {
      return
    }
    guard data.count > 8 else { return }
    let textureId = data.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }.littleEndian
    let payload = data.subdata(in: 8..<data.count)
    lock.lock()
    let texture = sessions[textureId]
    lock.unlock()
    texture?.decode(payload)
  }
}

/// A single decoded scrcpy stream surfaced as a Flutter texture.
final class ScrcpyVideoTexture: NSObject, FlutterTexture {
  private var textureId: Int64 = 0
  private weak var registry: FlutterTextureRegistry?

  private let decodeQueue = DispatchQueue(label: "eagly.scrcpy.decode")
  private var session: VTDecompressionSession?
  private var formatDescription: CMVideoFormatDescription?
  private var currentSps: [UInt8]?
  private var currentPps: [UInt8]?

  private let pixelLock = NSLock()
  private var latestPixelBuffer: CVPixelBuffer?

  func configure(textureId: Int64, registry: FlutterTextureRegistry) {
    self.textureId = textureId
    self.registry = registry
  }

  // MARK: FlutterTexture

  private var copyCount = 0

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    pixelLock.lock()
    defer { pixelLock.unlock() }
    guard let buffer = latestPixelBuffer else { return nil }
    copyCount += 1
    if copyCount == 1 {
      NSLog("[scrcpy] Flutter pulled first pixel buffer from texture \(textureId)")
    }
    return Unmanaged.passRetained(buffer)
  }

  // MARK: Decoding

  func decode(_ annexB: Data) {
    decodeQueue.async { [weak self] in
      self?.decodeOnQueue([UInt8](annexB))
    }
  }

  func shutdown() {
    decodeQueue.sync {
      if let session = session {
        VTDecompressionSessionWaitForAsynchronousFrames(session)
        VTDecompressionSessionInvalidate(session)
      }
      session = nil
      formatDescription = nil
    }
    pixelLock.lock()
    latestPixelBuffer = nil
    pixelLock.unlock()
  }

  private var decodedFrameCount = 0
  private var decodeErrorCount = 0

  fileprivate func onDecoded(_ imageBuffer: CVImageBuffer) {
    pixelLock.lock()
    latestPixelBuffer = imageBuffer
    pixelLock.unlock()
    decodedFrameCount += 1
    if decodedFrameCount == 1 {
      NSLog("[scrcpy] first frame decoded -> texture \(textureId)")
    }
    registry?.textureFrameAvailable(textureId)
  }

  private func decodeOnQueue(_ bytes: [UInt8]) {
    let units = Self.nalRanges(bytes)
    var newSps: [UInt8]?
    var newPps: [UInt8]?
    var slices: [[UInt8]] = []
    for range in units {
      let type = bytes[range.lowerBound] & 0x1F
      switch type {
      case 7: newSps = Array(bytes[range])
      case 8: newPps = Array(bytes[range])
      case 1, 5: slices.append(Array(bytes[range]))
      default: break  // SEI / AUD / etc. are not needed for display
      }
    }

    if let sps = newSps, let pps = newPps {
      NSLog("[scrcpy] config packet received (sps=\(sps.count) pps=\(pps.count))")
      updateFormat(sps: sps, pps: pps)
    }

    guard let format = formatDescription, let session = session else {
      if !slices.isEmpty {
        NSLog("[scrcpy] dropped \(slices.count) slice(s): no format/session yet")
      }
      return
    }
    for slice in slices {
      decodeSlice(slice, format: format, session: session)
    }
  }

  private func updateFormat(sps: [UInt8], pps: [UInt8]) {
    if sps == currentSps && pps == currentPps && session != nil { return }
    currentSps = sps
    currentPps = pps

    var format: CMFormatDescription?
    let status = sps.withUnsafeBufferPointer { spsBuf in
      pps.withUnsafeBufferPointer { ppsBuf in
        let pointers = [spsBuf.baseAddress!, ppsBuf.baseAddress!]
        let sizes = [sps.count, pps.count]
        return pointers.withUnsafeBufferPointer { ptrBuf in
          sizes.withUnsafeBufferPointer { sizeBuf in
            CMVideoFormatDescriptionCreateFromH264ParameterSets(
              allocator: kCFAllocatorDefault,
              parameterSetCount: 2,
              parameterSetPointers: ptrBuf.baseAddress!,
              parameterSetSizes: sizeBuf.baseAddress!,
              nalUnitHeaderLength: 4,
              formatDescriptionOut: &format)
          }
        }
      }
    }
    guard status == noErr, let format = format else {
      NSLog("[scrcpy] format description creation failed: \(status)")
      return
    }
    let dims = CMVideoFormatDescriptionGetDimensions(format)
    NSLog("[scrcpy] format ready \(dims.width)x\(dims.height) (sps=\(sps.count) pps=\(pps.count))")
    formatDescription = format
    rebuildSession(format: format)
  }

  private func rebuildSession(format: CMVideoFormatDescription) {
    if let old = session {
      VTDecompressionSessionInvalidate(old)
      session = nil
    }
    let attributes: [CFString: Any] = [
      kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
      kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any]() as CFDictionary,
      kCVPixelBufferMetalCompatibilityKey: true,
    ]
    var callback = VTDecompressionOutputCallbackRecord(
      decompressionOutputCallback: scrcpyDecompressionOutputCallback,
      decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque())
    var newSession: VTDecompressionSession?
    let status = VTDecompressionSessionCreate(
      allocator: kCFAllocatorDefault,
      formatDescription: format,
      decoderSpecification: nil,
      imageBufferAttributes: attributes as CFDictionary,
      outputCallback: &callback,
      decompressionSessionOut: &newSession)
    guard status == noErr, let newSession = newSession else {
      NSLog("[scrcpy] VTDecompressionSessionCreate failed: \(status)")
      return
    }
    VTSessionSetProperty(
      newSession, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
    session = newSession
    NSLog("[scrcpy] decompression session created")
  }

  private func decodeSlice(
    _ nal: [UInt8], format: CMVideoFormatDescription, session: VTDecompressionSession
  ) {
    // Convert Annex-B NAL to AVCC (4-byte big-endian length prefix).
    var avcc = [UInt8](repeating: 0, count: 4 + nal.count)
    let len = nal.count
    avcc[0] = UInt8((len >> 24) & 0xFF)
    avcc[1] = UInt8((len >> 16) & 0xFF)
    avcc[2] = UInt8((len >> 8) & 0xFF)
    avcc[3] = UInt8(len & 0xFF)
    avcc.replaceSubrange(4..<avcc.count, with: nal)

    var blockBuffer: CMBlockBuffer?
    var status = CMBlockBufferCreateWithMemoryBlock(
      allocator: kCFAllocatorDefault,
      memoryBlock: nil,
      blockLength: avcc.count,
      blockAllocator: kCFAllocatorDefault,
      customBlockSource: nil,
      offsetToData: 0,
      dataLength: avcc.count,
      flags: kCMBlockBufferAssureMemoryNowFlag,
      blockBufferOut: &blockBuffer)
    guard status == kCMBlockBufferNoErr, let blockBuffer = blockBuffer else { return }
    status = avcc.withUnsafeBytes {
      CMBlockBufferReplaceDataBytes(
        with: $0.baseAddress!, blockBuffer: blockBuffer, offsetIntoDestination: 0,
        dataLength: avcc.count)
    }
    guard status == kCMBlockBufferNoErr else { return }

    var sampleBuffer: CMSampleBuffer?
    var sampleSize = avcc.count
    status = CMSampleBufferCreateReady(
      allocator: kCFAllocatorDefault,
      dataBuffer: blockBuffer,
      formatDescription: format,
      sampleCount: 1,
      sampleTimingEntryCount: 0,
      sampleTimingArray: nil,
      sampleSizeEntryCount: 1,
      sampleSizeArray: &sampleSize,
      sampleBufferOut: &sampleBuffer)
    guard status == noErr, let sampleBuffer = sampleBuffer else { return }

    var flagsOut = VTDecodeInfoFlags()
    let decodeStatus = VTDecompressionSessionDecodeFrame(
      session,
      sampleBuffer: sampleBuffer,
      flags: [._EnableAsynchronousDecompression],
      frameRefcon: nil,
      infoFlagsOut: &flagsOut)
    if decodeStatus != noErr {
      decodeErrorCount += 1
      if decodeErrorCount <= 5 || decodeErrorCount % 30 == 0 {
        let dims = CMVideoFormatDescriptionGetDimensions(format)
        NSLog(
          "[scrcpy] decode frame failed: \(decodeStatus) "
            + "(format \(dims.width)x\(dims.height), error #\(decodeErrorCount))")
      }
    }
  }

  /// Returns the byte ranges of each NAL unit payload (start codes excluded).
  private static func nalRanges(_ bytes: [UInt8]) -> [Range<Int>] {
    let n = bytes.count
    var starts: [(pos: Int, len: Int)] = []
    var i = 0
    while i + 3 <= n {
      if bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 1 {
        starts.append((i, 3))
        i += 3
      } else if i + 4 <= n && bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 0
        && bytes[i + 3] == 1
      {
        starts.append((i, 4))
        i += 4
      } else {
        i += 1
      }
    }
    var ranges: [Range<Int>] = []
    for (index, start) in starts.enumerated() {
      let payloadStart = start.pos + start.len
      let payloadEnd = index + 1 < starts.count ? starts[index + 1].pos : n
      if payloadStart < payloadEnd {
        ranges.append(payloadStart..<payloadEnd)
      }
    }
    return ranges
  }
}

/// Free C-callback target for VideoToolbox; routes decoded frames back to the
/// owning texture via the refcon pointer.
private func scrcpyDecompressionOutputCallback(
  decompressionOutputRefCon: UnsafeMutableRawPointer?,
  sourceFrameRefCon: UnsafeMutableRawPointer?,
  status: OSStatus,
  infoFlags: VTDecodeInfoFlags,
  imageBuffer: CVImageBuffer?,
  presentationTimeStamp: CMTime,
  presentationDuration: CMTime
) {
  guard status == noErr, let imageBuffer = imageBuffer, let refCon = decompressionOutputRefCon
  else { return }
  let texture = Unmanaged<ScrcpyVideoTexture>.fromOpaque(refCon).takeUnretainedValue()
  texture.onDecoded(imageBuffer)
}
