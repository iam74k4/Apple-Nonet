// ポインタの位置を読む・動かす（scripts/demo/record.sh が使う）。
// デモの HUD はポインタの位置に開くので、台本を流す前に撮る範囲の真ん中へ動かし、収録が済んだら元の位置へ戻す。
// コンパイル: swiftc -O scripts/demo/pointer.swift -o build/demo-pointer
// 使い方: build/demo-pointer get → "x y"（主画面の左上が原点の pt）。build/demo-pointer set <x> <y> → そこへ動かす
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
if arguments.count == 4, arguments[1] == "set", let x = Double(arguments[2]), let y = Double(arguments[3]) {
    CGWarpMouseCursorPosition(CGPoint(x: x, y: y))
} else if arguments.count == 2, arguments[1] == "get", let location = CGEvent(source: nil)?.location {
    print("\(location.x) \(location.y)")
} else {
    FileHandle.standardError.write(Data("使い方: demo-pointer get | demo-pointer set <x> <y>\n".utf8))
    exit(2)
}
