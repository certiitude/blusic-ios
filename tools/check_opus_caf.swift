import Foundation
import AVFoundation

// Host-native smoke check, in addition to XCTest on the iPhone simulator.
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let file = try AVAudioFile(forReading: url)
precondition(file.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatOpus, "Not native Opus")
precondition(file.length > 0)
let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096)!
try file.read(into: buffer)
precondition(buffer.frameLength > 0, "No decoded Opus frames")
file.framePosition = file.length / 2
try file.read(into: buffer)
precondition(buffer.frameLength > 0, "Cannot seek Opus")
file.framePosition = max(0, file.length - 4096)
try file.read(into: buffer)
precondition(buffer.frameLength > 0, "Cannot decode Opus ending")
print("Native Opus CAF decoded and sought: \(Double(file.length) / file.processingFormat.sampleRate)s")
