import XCTest
@testable import DietCloud

final class BodyAnalysisMapperTests: XCTestCase {
    func testMakeRequestRequiresJPEGAndUsesDataURL() throws {
        let jpeg = Data(repeating: 0xAB, count: 16)
        let request = try BodyAnalysisRequest.make(jpegData: jpeg)
        XCTAssertTrue(request.screenshot.dataUrl.hasPrefix("data:image/jpeg;base64,"))
        XCTAssertEqual(request.screenshot.contentType, "image/jpeg")
        XCTAssertFalse(request.containsRemotePhotoURL)
    }

    func testMakeRequestRejectsEmptyData() {
        XCTAssertThrowsError(try BodyAnalysisRequest.make(jpegData: Data()))
    }

    func testRemoteDataURLFlag() {
        let remote = BodyAnalysisRequest(
            screenshot: BodyAnalysisScreenshotPayload(
                fileName: "x.jpg",
                contentType: "image/jpeg",
                dataUrl: "https://cdn.example/a.jpg"
            )
        )
        XCTAssertTrue(remote.containsRemotePhotoURL)
        XCTAssertFalse(remote.isLocalDataURL)

        let fileURL = BodyAnalysisRequest(
            screenshot: BodyAnalysisScreenshotPayload(
                fileName: "x.jpg",
                contentType: "image/jpeg",
                dataUrl: "file:///tmp/x.jpg"
            )
        )
        XCTAssertTrue(fileURL.containsRemotePhotoURL)

        let local = try! BodyAnalysisRequest.make(jpegData: Data(repeating: 0x1, count: 8))
        XCTAssertTrue(local.isLocalDataURL)
        XCTAssertFalse(local.containsRemotePhotoURL)
    }

    func testDTOMapperKeepsNullsAsNilNotZero() throws {
        let dto = BodyAnalysisAPIResponseDTO(
            ok: true,
            model: "m1",
            analysis: BodyAnalysisDTO(
                confidence: 0.9,
                date: "2026-07-10",
                measuredAt: "2026-07-10T07:30",
                score: nil,
                weightKg: 72.5,
                bmi: 22.1,
                bodyFatPercent: 18.2,
                bodyAge: nil,
                bodyType: "标准",
                muscleKg: 50,
                skeletalMuscleKg: nil,
                boneMassKg: 2.8,
                waterPercent: 55,
                visceralFat: 7,
                bmrKcal: 1480,
                proteinPercent: nil,
                trunkFatPercent: nil,
                trunkMuscleKg: nil,
                leftArmFatPercent: nil,
                leftArmMuscleKg: nil,
                rightArmFatPercent: nil,
                rightArmMuscleKg: nil,
                leftLegFatPercent: nil,
                leftLegMuscleKg: nil,
                rightLegFatPercent: nil,
                rightLegMuscleKg: nil,
                notes: "请核对"
            ),
            error: nil,
            code: nil
        )
        let result = try BodyAnalysisDTOMapper.domain(from: dto)
        XCTAssertEqual(result.weightKg, 72.5)
        XCTAssertNil(result.score)
        XCTAssertNil(result.skeletalMuscleKg)
        XCTAssertEqual(result.bodyType, "标准")
        XCTAssertEqual(result.date, "2026-07-10")
        XCTAssertEqual(result.notes, "请核对")
        XCTAssertEqual(result.model, "m1")
        XCTAssertFalse(result.isLowConfidence)
    }

    func testLowConfidenceFlag() {
        let result = BodyAnalysisResult(
            confidence: 0.4,
            date: nil,
            measuredAt: nil,
            score: nil,
            weightKg: 70,
            bmi: nil,
            bodyFatPercent: nil,
            bodyAge: nil,
            bodyType: nil,
            muscleKg: nil,
            skeletalMuscleKg: nil,
            boneMassKg: nil,
            waterPercent: nil,
            visceralFat: nil,
            bmrKcal: nil,
            proteinPercent: nil,
            trunkFatPercent: nil,
            trunkMuscleKg: nil,
            leftArmFatPercent: nil,
            leftArmMuscleKg: nil,
            rightArmFatPercent: nil,
            rightArmMuscleKg: nil,
            leftLegFatPercent: nil,
            leftLegMuscleKg: nil,
            rightLegFatPercent: nil,
            rightLegMuscleKg: nil,
            notes: "",
            model: nil
        )
        XCTAssertTrue(result.isLowConfidence)
    }

    func testFormFillOnlyAppliesPresentMetrics() {
        var draft = "旧值"
        BodyAnalysisFormFill.applyIfPresent(nil, onto: &draft)
        XCTAssertEqual(draft, "旧值")
        BodyAnalysisFormFill.applyIfPresent("72.5", onto: &draft)
        XCTAssertEqual(draft, "72.5")
    }
}
