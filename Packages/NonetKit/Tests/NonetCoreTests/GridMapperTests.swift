import Testing
import NonetCore

@Suite struct GridMapperTests {
    let grid = GridMapper()

    @Test(arguments: 0..<9)
    func cellCentersMapToRowMajorIndexFromTopLeft(cell: Int) {
        let point = Pad.center(cell)
        #expect(grid.cell(x: point.x, y: point.y) == cell)
    }

    @Test func yGrowsFromTheFrontEdge() {
        // 奥（y = 1）が上の行、手前（y = 0）が下の行
        #expect(grid.cell(x: 0.5, y: 0.95) == 1)
        #expect(grid.cell(x: 0.5, y: 0.05) == 7)
    }

    @Test func cornersAreReachable() {
        #expect(grid.cell(x: 0, y: 1) == 0)
        #expect(grid.cell(x: 1, y: 1) == 2)
        #expect(grid.cell(x: 0, y: 0) == 6)
        #expect(grid.cell(x: 1, y: 0) == 8)
    }

    @Test func outOfRangeCoordinatesAreClamped() {
        #expect(grid.cell(x: -0.3, y: 1.4) == 0)
        #expect(grid.cell(x: 1.7, y: -2) == 8)
        #expect(grid.cell(x: .infinity, y: -.infinity) == 8)
        #expect(grid.cell(x: -.infinity, y: .infinity) == 0)
    }

    @Test func nanIsTreatedAsTheMiddle() {
        #expect(grid.cell(x: .nan, y: .nan) == 4)
        #expect(grid.cell(x: .nan, y: 0.95) == 1)
        #expect(grid.cell(x: 0.05, y: .nan) == 3)
    }

    @Test func borderBelongsToTheNextCellWithoutHistory() {
        #expect(grid.cell(x: 1.0 / 3, y: 0.5) == 4)
        #expect(grid.cell(x: 1.0 / 3 - 0.0001, y: 0.5) == 3)
        #expect(grid.cell(x: 2.0 / 3, y: 0.5) == 5)
    }

    @Test func hysteresisKeepsTheCurrentCellNearABorder() {
        // 3（左の列）から右へ、境界 1/3 を 0.02 だけ越えても 3 のまま
        #expect(grid.cell(x: 1.0 / 3 + 0.02, y: 0.5, current: 3) == 3)
        // 0.03 を越えたら切り替わる
        #expect(grid.cell(x: 1.0 / 3 + 0.04, y: 0.5, current: 3) == 4)
        // 逆向き
        #expect(grid.cell(x: 1.0 / 3 - 0.02, y: 0.5, current: 4) == 4)
        #expect(grid.cell(x: 1.0 / 3 - 0.04, y: 0.5, current: 4) == 3)
    }

    @Test func hysteresisAlsoAppliesVertically() {
        // 1（上の行）と 4（中の行）の境界は y = 2/3
        #expect(grid.cell(x: 0.5, y: 2.0 / 3 - 0.02, current: 1) == 1)
        #expect(grid.cell(x: 0.5, y: 2.0 / 3 - 0.04, current: 1) == 4)
        #expect(grid.cell(x: 0.5, y: 2.0 / 3 + 0.02, current: 4) == 4)
    }

    @Test func jitterAcrossABorderStaysInOneCell() {
        var current = grid.cell(x: 0.32, y: 0.5)
        #expect(current == 3)
        for x in [0.34, 0.33, 0.355, 0.31, 0.36, 0.335] {
            current = grid.cell(x: x, y: 0.5, current: current)
            #expect(current == 3)
        }
    }

    @Test func jumpingFarAwayIgnoresTheCurrentCell() {
        #expect(grid.cell(x: 0.95, y: 0.05, current: 0) == 8)
    }

    @Test func diagonalMoveNearACornerKeepsTheCurrentCellOnlyWhenInsideBothMargins() {
        // 0 と 4 の角（1/3, 2/3）のすぐ外側
        #expect(grid.cell(x: 1.0 / 3 + 0.01, y: 2.0 / 3 - 0.01, current: 0) == 0)
        #expect(grid.cell(x: 1.0 / 3 + 0.01, y: 2.0 / 3 - 0.05, current: 0) == 4)
    }

    @Test func invalidCurrentCellIsIgnored() {
        #expect(grid.cell(x: 0.36, y: 0.5, current: 9) == 4)
        #expect(grid.cell(x: 0.36, y: 0.5, current: -1) == 4)
    }

    @Test func zeroHysteresisSwitchesAtTheBorder() {
        let sharp = GridMapper(hysteresis: 0)
        #expect(sharp.cell(x: 1.0 / 3 + 0.001, y: 0.5, current: 3) == 4)
    }

    @Test func hysteresisIsSanitized() {
        #expect(GridMapper(hysteresis: -1).hysteresis == 0)
        #expect(GridMapper(hysteresis: 0.9).hysteresis == GridMapper.maxHysteresis)
        #expect(GridMapper(hysteresis: .nan).hysteresis == GridMapper.defaultHysteresis)
        #expect(GridMapper(hysteresis: .infinity).hysteresis == GridMapper.defaultHysteresis)
        #expect(GridMapper().hysteresis == 0.03)
    }

    @Test func maximumHysteresisStillSwitchesAtTheNeighborsCenter() {
        let sticky = GridMapper(hysteresis: 1)
        #expect(sticky.cell(x: 0.49, y: 0.5, current: 3) == 3)
        #expect(sticky.cell(x: 0.51, y: 0.5, current: 3) == 4)
    }

    @Test func edgeInsetsMakeTheReachableAreaEqualThirds() {
        // センサーが 0.1〜0.9 しか返さない機種: 境界は 0.1 + 0.8/3 ≈ 0.367 と 0.633
        let inset = GridMapper(hysteresis: 0, insets: GridInsets(all: 0.1))
        #expect(inset.cell(x: 0.35, y: 0.5) == 3)
        #expect(grid.cell(x: 0.35, y: 0.5) == 4)
        #expect(inset.cell(x: 0.65, y: 0.5) == 5)
        #expect(inset.cell(x: 0.1, y: 0.9) == 0)
        #expect(inset.cell(x: 0.9, y: 0.1) == 8)
        // 縁より外は端のマス
        #expect(inset.cell(x: 0.02, y: 0.98) == 0)
    }

    @Test func edgeInsetsCanDifferPerSide() {
        let inset = GridMapper(hysteresis: 0, insets: GridInsets(left: 0.2, right: 0, bottom: 0, top: 0.1))
        // 列の幅は 0.8/3。左の列は 0.2〜0.467
        #expect(inset.cell(x: 0.45, y: 0.5) == 3)
        #expect(inset.cell(x: 0.48, y: 0.5) == 4)
        // 行の高さは 0.9/3。上の行は 0.6〜0.9
        #expect(inset.cell(x: 0.5, y: 0.61) == 1)
        #expect(inset.cell(x: 0.5, y: 0.59) == 4)
    }

    @Test func hysteresisIsMeasuredInPadUnitsEvenWithInsets() {
        let inset = GridMapper(hysteresis: 0.03, insets: GridInsets(all: 0.1))
        let border = 0.1 + 0.8 / 3
        #expect(inset.cell(x: border + 0.025, y: 0.5, current: 3) == 3)
        #expect(inset.cell(x: border + 0.035, y: 0.5, current: 3) == 4)
    }

    @Test func insetsAreSanitized() {
        let insets = GridInsets(left: 0.6, right: -1, bottom: .nan, top: .infinity)
        #expect(insets == GridInsets(left: GridInsets.maxInset, right: 0, bottom: 0, top: 0))
        #expect(GridInsets.zero == GridInsets(all: 0))
        // 両側を上限にしても使える範囲は残る
        let widest = GridMapper(hysteresis: 0, insets: GridInsets(all: 5))
        #expect(widest.cell(x: 0.3, y: 0.7) == 0)
        #expect(widest.cell(x: 0.5, y: 0.5) == 4)
        #expect(widest.cell(x: 0.7, y: 0.3) == 8)
    }

    @Test func touchPointOverloadUsesItsCoordinates() {
        let point = TouchPoint(id: 3, x: 0.9, y: 0.9)
        #expect(grid.cell(for: point) == 2)
        #expect(grid.cell(for: TouchPoint(id: 3, x: 0.68, y: 0.9), current: 1) == 1)
    }
}
