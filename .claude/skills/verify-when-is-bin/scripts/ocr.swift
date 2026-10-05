// Prints every line of text Vision finds in a PNG, one per line, as
// "<text>\t<centre-x>\t<centre-y>" in image pixels (origin top left).
// Used by tap_system_button.sh to find an iOS system alert button (which the
// Flutter test cannot see) without hard-coded coordinates.
// Usage: xcrun swift ocr.swift <image.png>
import AppKit
import Vision

let path = CommandLine.arguments[1]
guard let image = NSImage(contentsOfFile: path),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
  FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!)
  exit(1)
}
let width = Double(cg.width), height = Double(cg.height)
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
try VNImageRequestHandler(cgImage: cg).perform([request])
for observation in request.results ?? [] {
  guard let text = observation.topCandidates(1).first?.string else { continue }
  let box = observation.boundingBox  // normalised, origin bottom left
  let x = (box.midX * width).rounded()
  let y = ((1 - box.midY) * height).rounded()
  print("\(text)\t\(Int(x))\t\(Int(y))")
}
