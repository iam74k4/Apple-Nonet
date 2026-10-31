// 担当: engine。すぐにタップを受け付けない境界の帯（GridMapper.boundaryBand）
import Testing
import NonetCore

@Suite struct GridMapperBoundaryBandTests {
    let grid = GridMapper()
    /// 内側の境界の線（縦は x、横は y。どちらも 1/3 と 2/3）
    static let lines = [1.0 / 3, 2.0 / 3]

    @Test func theBandIsNarrowerThanTheHysteresisAndLeavesMostOfEachCell() {
        #expect(GridMapper.defaultBoundaryBand == 0.025)
        #expect(grid.boundaryBand == GridMapper.defaultBoundaryBand)
        // 帯はヒステリシス（来た向きでどちらのマスにもなる幅）の内側に収める
        #expect(GridMapper.defaultBoundaryBand < GridMapper.defaultHysteresis)
        // 両側に線がある中央のマスでも、幅の 85% はタップを受け付ける
        let cell = 1.0 / 3
        #expect(abs((cell - 2 * GridMapper.defaultBoundaryBand) / cell - 0.85) < 1e-9)
    }

    @Test(arguments: lines)
    func landingExactlyOnALineIsInTheBand(line: Double) {
        // 線の上で、もう一方の向きはマスの中央（上の行・左の列）
        #expect(grid.isInBoundaryBand(x: line, y: 5.0 / 6))
        #expect(grid.isInBoundaryBand(x: 1.0 / 6, y: line))
    }

    @Test(arguments: lines)
    func insideTheBandOnEitherSideOfALine(line: Double) {
        for offset in [-0.024, -0.01, 0.01, 0.024] {
            #expect(grid.isInBoundaryBand(x: line + offset, y: 1.0 / 6), "x \(line + offset)")
            #expect(grid.isInBoundaryBand(x: 1.0 / 6, y: line + offset), "y \(line + offset)")
        }
    }

    @Test(arguments: lines)
    func outsideTheBandOnEitherSideOfALine(line: Double) {
        for offset in [-0.03, -0.026, 0.026, 0.03] {
            #expect(!grid.isInBoundaryBand(x: line + offset, y: 1.0 / 6), "x \(line + offset)")
            #expect(!grid.isInBoundaryBand(x: 1.0 / 6, y: line + offset), "y \(line + offset)")
        }
    }

    @Test(arguments: 0..<9)
    func cellCentersAreOutsideTheBand(cell: Int) {
        let point = Pad.center(cell, in: .zero)
        #expect(!grid.isInBoundaryBand(x: point.x, y: point.y))
    }

    /// 2本の線が交わる角: どちらかの線の帯に入れば帯の中
    @Test func cornersWhereTwoLinesCross() {
        for x in Self.lines {
            for y in Self.lines {
                #expect(grid.isInBoundaryBand(x: x, y: y))
                #expect(grid.isInBoundaryBand(x: x + 0.02, y: y - 0.02))
                // 片方の線の帯にだけ入っていても帯の中
                #expect(grid.isInBoundaryBand(x: x + 0.02, y: y + 0.1))
                #expect(grid.isInBoundaryBand(x: x - 0.1, y: y - 0.02))
                // 角のすぐ外（どちらの帯にも入らない）
                #expect(!grid.isInBoundaryBand(x: x + 0.03, y: y - 0.03))
                #expect(!grid.isInBoundaryBand(x: x - 0.03, y: y + 0.03))
            }
        }
    }

    /// トラックパッドの縁は境界ではない（端のマスは縁まで使える）
    @Test func theOuterEdgesAreNotBoundaries() {
        for edge in [0.0, 0.005, 0.02, 0.98, 0.995, 1.0] {
            #expect(!grid.isInBoundaryBand(x: edge, y: 1.0 / 6), "x \(edge)")
            #expect(!grid.isInBoundaryBand(x: 1.0 / 6, y: edge), "y \(edge)")
        }
        #expect(!grid.isInBoundaryBand(x: 0, y: 0))
        #expect(!grid.isInBoundaryBand(x: 1, y: 1))
        // 範囲の外の値は縁に寄せる
        #expect(!grid.isInBoundaryBand(x: -0.5, y: 1.5))
        #expect(!grid.isInBoundaryBand(x: .infinity, y: -.infinity))
    }

    @Test func nanIsTreatedAsTheMiddleOfTheCenterCell() {
        #expect(!grid.isInBoundaryBand(x: .nan, y: .nan))
        #expect(grid.isInBoundaryBand(x: .nan, y: 1.0 / 3))
    }

    @Test func aZeroBandNeverRejects() {
        let none = GridMapper(boundaryBand: 0)
        for line in Self.lines {
            #expect(!none.isInBoundaryBand(x: line, y: line))
        }
    }

    @Test func theBandIsSanitized() {
        #expect(GridMapper(boundaryBand: -1).boundaryBand == 0)
        #expect(GridMapper(boundaryBand: .nan).boundaryBand == GridMapper.defaultBoundaryBand)
        #expect(GridMapper(boundaryBand: .infinity).boundaryBand == GridMapper.defaultBoundaryBand)
        // 大きすぎる帯でもマスの 1/4 で止め、中央のマスの真ん中は受け付ける
        let wide = GridMapper(boundaryBand: 0.3)
        #expect(!wide.isInBoundaryBand(x: 0.5, y: 0.5))
        #expect(wide.isInBoundaryBand(x: 1.0 / 3 + 0.08, y: 0.5))
        #expect(!wide.isInBoundaryBand(x: 1.0 / 3 + 0.09, y: 0.5))
    }

    /// 縁を除くと線の位置が変わる。帯の幅はヒステリシスと同じくトラックパッド単位
    @Test func edgeInsetsMoveTheLines() {
        let inset = GridMapper(insets: GridInsets(all: 0.1))
        let line = 0.1 + 0.8 / 3
        #expect(inset.isInBoundaryBand(x: line, y: 0.5))
        #expect(inset.isInBoundaryBand(x: line + 0.024, y: 0.5))
        #expect(!inset.isInBoundaryBand(x: line + 0.026, y: 0.5))
        // 縁を除かないときの線（1/3）は、もう線ではない
        #expect(!inset.isInBoundaryBand(x: 1.0 / 3, y: 0.5))
        // 縁より外は端のマスで、線ではない
        #expect(!inset.isInBoundaryBand(x: 0.05, y: 0.95))
    }

    @Test func touchPointOverloadUsesItsCoordinates() {
        #expect(grid.isInBoundaryBand(TouchPoint(id: 1, x: 1.0 / 3, y: 0.9)))
        #expect(!grid.isInBoundaryBand(TouchPoint(id: 1, x: 0.9, y: 0.9)))
    }
}
