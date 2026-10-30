// 担当: ui-settings
// インスペクタでの変更（種類・送るキー・アプリ・切り替え・アイコン・表示名など）を、マスごとに1つの取り消しにまとめる。
// 同じマスを続けて変えている間は1つにし、別のマスを選ぶ・ほかの操作をする・元に戻すと閉じる。
// 文字の欄を打っている間の変更は、打ち終わってから積む。欄の打ち込みの取り消し（欄の中だけで効く）より上に積むと、
// ⌘Z でマスの中身が先に戻って欄の文字が入れ替わり、残った欄の取り消しが合わなくなるため
import AppKit
import NonetCore

extension SettingsModel {
    /// インスペクタでの変更の取り消しの名前
    static var inspectorEditActionName: String {
        String(localized: "ボタンの変更", bundle: .module)
    }

    /// インスペクタでマスを変えた（updateCell から）。同じマスを続けて変えている間は、変える前の中身に戻す1つの取り消しにまとめる
    func recordInspectorEdit(cellID: UUID, profileID: UUID, address: CellAddress, before: Cell) {
        // 元に戻している間（打ちかけの確定など）の変更は積まない（積むとやり直しの側に入ってしまう）
        guard !undoManager.isUndoing, !undoManager.isRedoing else {
            editGroup = nil
            return
        }
        let after = SettingsCellSnapshot(address: address, cell: cellSnapshots(at: [address], profileID: profileID).first?.cell)
        if let group = editGroup, group.cellID == cellID, group.profileID == profileID, group.before.address == address {
            group.after = after
        } else {
            closeEditGroup()
            editGroup = SettingsCellEditGroup(
                cellID: cellID,
                profileID: profileID,
                before: SettingsCellSnapshot(address: address, cell: before),
                after: after
            )
        }
        if let group = editGroup, !group.isRegistered, !isEditingText() {
            registerEditGroup(group)
        }
    }

    /// まとまりを閉じる。打ち終わるのを待っていたものは、ここで積む（元に戻している間は積まずに忘れる）
    func closeEditGroup() {
        guard let group = editGroup else { return }
        editGroup = nil
        if !group.isRegistered, !undoManager.isUndoing, !undoManager.isRedoing {
            registerEditGroup(group)
        }
    }

    /// 文字の欄を打ち終えた（NSText.didEndEditingNotification）。ほかの欄に移っただけなら、その欄を打ち終えるまで待つ
    func textEditingDidEnd() {
        guard let group = editGroup, !group.isRegistered, !isEditingText() else { return }
        registerEditGroup(group)
    }

    /// 元に戻す・やり直す前。積んだまとまりはここで閉じ、後の変更は新しいまとまりにする
    func undoManagerWillChange() {
        if editGroup?.isRegistered == true {
            editGroup = nil
        }
    }

    /// 戻すときは、そのときの after（最後に変えた中身）と今の中身が同じかを確かめる（restoreCells）
    private func registerEditGroup(_ group: SettingsCellEditGroup) {
        guard group.before != group.after else { return }
        group.isRegistered = true
        let name = Self.inspectorEditActionName
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: undoTarget(for: group.profileID)) { [weak self, group] _ in
            self?.restoreCells([group.before], expecting: [group.after], profileID: group.profileID, actionName: name)
        }
        undoManager.setActionName(name)
        undoManager.endUndoGrouping()
    }
}
