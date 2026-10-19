import Foundation

guard CommandLine.arguments.count >= 4, CommandLine.arguments.count.isMultiple(of: 2) else {
    fputs("usage: IconPacker <output.icns> <fourcc> <image.png> [...]\n", stderr)
    exit(2)
}

func bigEndianData(_ value: UInt32) -> Data {
    var encoded = value.bigEndian
    return Data(bytes: &encoded, count: MemoryLayout<UInt32>.size)
}

var chunks = Data()
var index = 2
while index < CommandLine.arguments.count {
    let type = CommandLine.arguments[index]
    let path = CommandLine.arguments[index + 1]
    guard type.utf8.count == 4 else {
        fputs("invalid ICNS chunk type: \(type)\n", stderr)
        exit(2)
    }

    do {
        let image = try Data(contentsOf: URL(fileURLWithPath: path))
        chunks.append(Data(type.utf8))
        chunks.append(bigEndianData(UInt32(image.count + 8)))
        chunks.append(image)
    } catch {
        fputs("unable to read \(path): \(error.localizedDescription)\n", stderr)
        exit(1)
    }
    index += 2
}

var container = Data("icns".utf8)
container.append(bigEndianData(UInt32(chunks.count + 8)))
container.append(chunks)

do {
    try container.write(
        to: URL(fileURLWithPath: CommandLine.arguments[1]),
        options: .atomic
    )
} catch {
    fputs("unable to write ICNS: \(error.localizedDescription)\n", stderr)
    exit(1)
}
