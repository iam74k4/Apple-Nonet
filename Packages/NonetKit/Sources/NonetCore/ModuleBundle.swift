import Foundation

extension Bundle {
    /// NonetCore の文言の置き場所。同じパッケージのテストが、実行環境の言語で期待値を引くのに使う
    package static var nonetCore: Bundle { .module }
}
