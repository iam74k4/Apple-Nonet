// 担当: engine。外枠（やめる場所）と9マスの境目（GridMapper.zone）
import NonetCore
import Testing

@Suite struct GridMapperFrameTests {
    let grid = GridMapper(insets: .cancelFrame)
    let frame = GridInsets.cancelFrame

    @Test func theFrameSurroundsTheGrid() {
        #expect(grid.zone(x: 0.5, y: 0.94) == .frame)
        #expect(grid.zone(x: 0.5, y: 0.05) == .frame)
        #expect(grid.zone(x: 0.03, y: 0.5) == .frame)
        #expect(grid.zone(x: 0.97, y: 0.5) == .frame)
        #expect(grid.zone(x: 0.5, y: 0.5) == .cell(4))
        #expect(grid.zone(x: 0.15, y: 0.8) == .cell(0))
        #expect(grid.zone(x: 0.85, y: 0.2) == .cell(8))
        // 境目ちょうどは9マスの中
        #expect(grid.zone(x: frame.left, y: 0.5) == .cell(3))
        #expect(grid.zone(x: 0.5, y: 1 - frame.top) == .cell(1))
        // センサーの異常値は外枠（離しても実行しない）
        #expect(grid.zone(x: .nan, y: 0.5) == .frame)
    }

    /// マスから外枠へは frameHysteresis 出てから、外枠からマスへは frameHysteresis 入ってから切り替わる
    @Test func theFrameEdgeHasHysteresis() {
        let margin = GridMapper.defaultFrameHysteresis
        let edge = frame.left
        #expect(grid.zone(x: edge - margin / 2, y: 0.5, current: .cell(3)) == .cell(3))
        #expect(grid.zone(x: edge - margin - 0.001, y: 0.5, current: .cell(3)) == .frame)
        #expect(grid.zone(x: edge + margin / 2, y: 0.5, current: .frame) == .frame)
        #expect(grid.zone(x: edge + margin + 0.001, y: 0.5, current: .frame) == .cell(3))
        // 新しく見る指は、ヒステリシス無しで決める
        #expect(grid.zone(x: edge - 0.001, y: 0.5) == .frame)
        #expect(grid.zone(x: edge + 0.001, y: 0.5) == .cell(3))
        // 上の縁から入ってくる指
        let top = 1 - frame.top
        #expect(grid.zone(x: 0.5, y: top - margin / 2, current: .frame) == .frame)
        #expect(grid.zone(x: 0.5, y: top - margin - 0.001, current: .frame) == .cell(1))
    }

    /// 9マスの中では、これまでどおりマスの境界のヒステリシスで今のマスを保つ
    @Test func cellsInsideKeepTheirHysteresis() {
        let line = frame.left + (1 - frame.left - frame.right) / 3
        #expect(grid.zone(x: line + 0.01, y: 0.5, current: .cell(3)) == .cell(3))
        #expect(grid.zone(x: line + GridMapper.defaultHysteresis + 0.01, y: 0.5, current: .cell(3)) == .cell(4))
    }

    /// 外枠の無いグリッドでは、トラックパッドの全体が9マス
    @Test func withoutAFrameEverythingIsACell() {
        let full = GridMapper()
        #expect(full.frameHysteresis == 0)
        #expect(full.zone(x: 0, y: 1) == .cell(0))
        #expect(full.zone(x: 1, y: 0) == .cell(8))
        #expect(GridZone.frame.cell == nil)
        #expect(GridZone.cell(5).cell == 5)
    }

    /// 指を離しても実行しない境界の帯は、外枠の内側のマスの境界の線のまわり
    @Test func theBoundaryBandFollowsTheInnerLines() {
        let line = frame.left + (1 - frame.left - frame.right) / 3
        #expect(grid.isInBoundaryBand(x: line, y: 0.5))
        #expect(grid.isInBoundaryBand(x: line + GridMapper.defaultBoundaryBand - 0.001, y: 0.5))
        #expect(!grid.isInBoundaryBand(x: line + GridMapper.defaultBoundaryBand + 0.002, y: 0.5))
        // マスの中央は帯の外
        for cell in 0..<9 {
            let center = Pad.center(cell)
            #expect(!grid.isInBoundaryBand(x: center.x, y: center.y), "cell \(cell)")
            #expect(grid.zone(x: center.x, y: center.y) == .cell(cell), "cell \(cell)")
        }
    }
}
