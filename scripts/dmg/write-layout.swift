// Writes the layout of the window of Scrollio's disk image.
//
//   swift scripts/dmg/write-layout.swift            writes scripts/dmg/DS_Store
//   swift scripts/dmg/write-layout.swift <file>     writes it somewhere else
//
// The layout is the file Finder reads as `.DS_Store` at the top of the image: how large
// the window is and that it has no toolbar or sidebar, the icon view's settings (icon and
// text size, the picture behind the icons) and where each icon sits. `stage_disk_image`
// in scripts/release-lib.sh copies it onto the image under that name.
//
// It is written here and not by Finder for two reasons. Finder writes this file only when
// it is scripted or used by hand, which a release run must not need. And Finder's own
// file says where it was made: the alias and the bookmark of the picture carry the path
// of the image file it was written on, the name of that Mac's disk and the user's name
// and number, into every download. This file holds what stands below and nothing else.
//
// Finder finds the picture through an alias. The alias names the volume ("Scrollio") and
// the path on it (/.background/background.tiff); the dates and file numbers an alias also
// has are zero, because every release's image is a new volume with other ones. The system
// then looks the volume up by its name. So the image must keep that volume name and that
// path (ReleaseReadinessTests compares them), and when two images named Scrollio are open
// at once, both windows take the picture from the first.
//
// The format: a "Bud1" store, which is a small allocator of blocks with a B-tree of
// records in it, as the open-source ds_store and mac_alias projects describe it. The
// blocks are placed the way Finder places them in a file with a single tree node.
import Foundation

// MARK: - The window (scripts/dmg/draw-background.swift draws the picture for these numbers)

/// The image's volume name: APP_NAME in scripts/release-lib.sh.
let volumeName = "Scrollio"
/// Where `stage_disk_image` puts the picture.
let pictureFolder = ".background"
let pictureFile = "background.tiff"

/// The part of the window below its title bar, in points: the picture's size.
let contentWidth = 660
let contentHeight = 420
/// Finder stores the window with its title bar: 28 pt on macOS 14 and 15. Where the bar
/// is higher (32 pt on macOS 27), the lowest 4 pt of the picture are not seen; a number
/// that fits those systems would show a strip without picture on the older ones.
let titleBarHeight = 28
/// Where the window opens on the screen.
let windowLeft = 200
let windowTop = 160

let iconSize = 128.0
let textSize = 13.0

/// The centre of each icon, from the top left corner of the window's content. The app and
/// the Applications folder stand at the two ends of the picture's arrow. The two text files
/// lie below what the window shows when it opens: they are on the image for whoever looks
/// for them, and the window shows two icons.
let icons: [(name: String, x: Int, y: Int)] = [
    ("Scrollio.app", 180, 184),
    ("Applications", 480, 184),
    ("LICENSE.txt", 180, 560),
    ("Acknowledgements.txt", 480, 560),
]

// MARK: - Bytes

extension Data {
    mutating func add(_ value: UInt32) { Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) } }
    mutating func add(_ value: UInt16) { Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) } }
    mutating func add(ascii text: String) { append(contentsOf: Array(text.utf8)) }
    /// Zeros up to `length` bytes.
    mutating func pad(to length: Int) {
        precondition(count <= length, "\(count) bytes do not fit \(length)")
        append(Data(count: length - count))
    }
}

// MARK: - The alias of the picture

/// An alias record (version 2) of /.background/background.tiff on the volume "Scrollio".
func pictureAlias() -> Data {
    /// A length byte and the text, in a field of fixed width.
    func pascal(_ text: String, width: Int) -> Data {
        let bytes = Array(text.utf8)
        precondition(bytes.count < width, "\(text) is too long for an alias")
        var field = Data([UInt8(bytes.count)] + bytes)
        field.pad(to: width)
        return field
    }
    func unicode(_ text: String) -> Data {
        let units = Array(text.utf16)
        var field = Data()
        field.add(UInt16(units.count))
        units.forEach { field.add($0) }
        return field
    }
    /// A numbered piece after the fixed part, padded to an even length.
    func tagged(_ number: UInt16, _ value: Data) -> Data {
        var piece = Data()
        piece.add(number)
        piece.add(UInt16(value.count))
        piece.append(value)
        if value.count % 2 == 1 { piece.append(0) }
        return piece
    }

    var body = Data()
    body.add(UInt16(0))                              // kind: a file
    body.append(pascal(volumeName, width: 28))
    body.add(UInt32(0))                              // the volume's creation date: not known
    body.add(ascii: "H+")                            // the file system: HFS+
    body.add(UInt16(5))                              // the kind of disk: one that can be ejected
    body.add(UInt32(0))                              // the folder's file number: not known
    body.append(pascal(pictureFile, width: 64))
    body.add(UInt32(0))                              // the file's number: not known
    body.add(UInt32(0))                              // the file's creation date: not known
    body.append(Data(count: 8))                      // creator and type: none
    body.add(UInt16(0xFFFF))                         // -1 and -1: not a relative alias
    body.add(UInt16(0xFFFF))
    body.add(UInt32(0x0D02))                         // volume attributes, as Finder writes them for a disk image
    body.append(Data(count: 12))                     // file system id, reserved
    // The same pieces, in the same order, as in an alias Finder writes for such a picture,
    // without its dates and without the alias of the image file.
    body.append(tagged(0, Data(pictureFolder.utf8)))
    body.append(tagged(1, { var ids = Data(); ids.add(UInt32(0)); return ids }()))
    body.append(tagged(2, Data("\(volumeName):\(pictureFolder):".utf8) + [0] + Data(pictureFile.utf8)))
    body.append(tagged(14, unicode(pictureFile)))
    body.append(tagged(15, unicode(volumeName)))
    body.append(tagged(18, Data("/\(pictureFolder)/\(pictureFile)".utf8)))
    body.append(tagged(19, Data("/Volumes/\(volumeName)".utf8)))
    body.add(UInt16(0xFFFF))                         // the end
    body.add(UInt16(0))

    var alias = Data(count: 4)                       // no application's mark
    alias.add(UInt16(8 + body.count))                // the record's length
    alias.add(UInt16(2))                             // version 2
    alias.append(body)
    return alias
}

// MARK: - The records

/// One entry of the store: a file's name ("." is the folder itself), a four-letter id,
/// the type of the value and the value as that type is stored.
struct Record {
    let name: String
    let id: String
    let type: String
    let value: Data

    var bytes: Data {
        let units = Array(name.utf16)
        var data = Data()
        data.add(UInt32(units.count))
        units.forEach { data.add($0) }
        data.add(ascii: id)
        data.add(ascii: type)
        data.append(value)
        return data
    }
}

func blob(_ value: Data) -> Data {
    var data = Data()
    data.add(UInt32(value.count))
    data.append(value)
    return data
}

/// A binary property list, as Finder stores the window's and the view's settings.
func propertyList(_ pairs: KeyValuePairs<String, Any>) -> Data {
    let dictionary = NSMutableDictionary()
    for (key, value) in pairs { dictionary[key] = value }
    return try! PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
}

func records() -> [Record] {
    let window = propertyList([
        "WindowBounds": "{{\(windowLeft), \(windowTop)}, {\(contentWidth), \(contentHeight + titleBarHeight)}}",
        "ShowToolbar": false,
        "ShowSidebar": false,
        "ContainerShowSidebar": false,
        "ShowStatusBar": false,
        "ShowPathbar": false,
        "ShowTabView": false,
    ])
    let iconView = propertyList([
        "viewOptionsVersion": 1,
        "arrangeBy": "none",                         // each icon stays where it is put
        "iconSize": iconSize,
        "textSize": textSize,
        "labelOnBottom": true,
        "showItemInfo": false,
        "showIconPreview": true,
        "gridSpacing": 100.0,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "backgroundType": 2,                         // a picture
        "backgroundImageAlias": pictureAlias(),
        "backgroundColorRed": 1.0,
        "backgroundColorGreen": 1.0,
        "backgroundColorBlue": 1.0,
    ])
    var all = [
        Record(name: ".", id: "bwsp", type: "blob", value: blob(window)),
        Record(name: ".", id: "icvp", type: "blob", value: blob(iconView)),
        Record(name: ".", id: "vSrn", type: "long", value: { var one = Data(); one.add(UInt32(1)); return one }()),
    ]
    for icon in icons {
        var place = Data()
        place.add(UInt32(icon.x))
        place.add(UInt32(icon.y))
        place.add(UInt32(0xFFFF_FFFF))
        place.add(UInt32(0xFFFF_0000))
        all.append(Record(name: icon.name, id: "Iloc", type: "blob", value: blob(place)))
    }
    // The tree keeps them in order: by name without regard to case, then by id.
    return all.sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
}

// MARK: - The store

/// The whole file: the header, the head of the tree, one tree node with every record, and
/// the allocator's list of blocks. Offsets inside the file count from after its first four
/// bytes; a block is named by its offset with the power of two of its size in the low bits.
func store(_ records: [Record]) -> Data {
    let nodeSize = 4096
    let treeHead = (offset: 0x40, power: 5)
    let node = (offset: 0x1000, power: 12)
    let blockList = (offset: 0x2000, power: 11)
    let blocks = [blockList, treeHead, node]         // block 0, 1 and 2

    // The one node: a leaf (no child), the number of records, the records.
    var leaf = Data()
    leaf.add(UInt32(0))
    leaf.add(UInt32(records.count))
    records.forEach { leaf.append($0.bytes) }
    precondition(leaf.count <= nodeSize, "the records no longer fit one node of the tree")
    leaf.pad(to: nodeSize)

    var head = Data()
    head.add(UInt32(2))                              // the root node is block 2
    head.add(UInt32(0))                              // no level below it
    head.add(UInt32(records.count))
    head.add(UInt32(1))                              // one node
    head.add(UInt32(nodeSize))
    head.pad(to: 1 << treeHead.power)

    // What the header and the three blocks leave free of the 2 GB the allocator counts
    // with: for each power of two the offsets of the free blocks of that size.
    let used = [0..<32] + blocks.map { $0.offset..<($0.offset + (1 << $0.power)) }
    var free = [[Int]](repeating: [], count: 32)
    func split(_ offset: Int, _ power: Int) {
        let block = offset..<(offset + (1 << power))
        if !used.contains(where: { $0.overlaps(block) }) {
            free[power].append(offset)
        } else if !used.contains(where: { $0.lowerBound <= block.lowerBound && block.upperBound <= $0.upperBound }) {
            split(offset, power - 1)
            split(offset + (1 << (power - 1)), power - 1)
        }
    }
    split(0, 31)

    var list = Data()
    list.add(UInt32(blocks.count))
    list.add(UInt32(0))
    blocks.forEach { list.add(UInt32($0.offset | $0.power)) }
    list.pad(to: 8 + 256 * 4)                        // room for 256 blocks
    list.add(UInt32(1))                              // one named block: the tree's head
    list.append(4)
    list.add(ascii: "DSDB")
    list.add(UInt32(1))
    for offsets in free {
        list.add(UInt32(offsets.count))
        offsets.forEach { list.add(UInt32($0)) }
    }
    list.pad(to: 1 << blockList.power)

    var file = Data()
    file.add(UInt32(1))
    file.add(ascii: "Bud1")
    file.add(UInt32(blockList.offset))
    file.add(UInt32(1 << blockList.power))
    file.add(UInt32(blockList.offset))
    file.add(UInt32(node.offset | node.power))
    file.pad(to: 4 + treeHead.offset)
    file.append(head)
    file.pad(to: 4 + node.offset)
    file.append(leaf)
    file.pad(to: 4 + blockList.offset)
    file.append(list)
    return file
}

// MARK: - Write

let script = URL(fileURLWithPath: #filePath)
let out = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : script.deletingLastPathComponent().appendingPathComponent("DS_Store")
let layout = store(records())
try layout.write(to: out)
print("wrote \(out.path): \(layout.count) bytes, a \(contentWidth) x \(contentHeight) pt window with \(icons.count) icons")
