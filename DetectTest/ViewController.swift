//
//  ViewController.swift
//  DetectTest
//
//  Created by MinhHieu on 15/01/2025.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreML
import UIKit
import Vision

class ViewController: UIViewController {
    @IBOutlet var imageTest: UIImageView!
    @IBOutlet var clv: UICollectionView!

    var croppedImages: [UIImage] = [] // Mảng lưu các ảnh con

    let model = try! DeepLabV3(configuration: MLModelConfiguration()) // Tải mô hình

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.

        // Ảnh gốc chứa nhiều hình
        guard let largeImage = UIImage(named: "image_test_14") else {
            print("Không thể tải ảnh gốc")
            return
        }

        // Phát hiện và crop ảnh
        self.detectAndCropImages(from: largeImage)

        // setupCollectionView
        self.clv.delegate = self
        self.clv.dataSource = self
        self.clv.contentInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        self.clv.register(cellType: CellTextImage.self)
    }

    func detectAndCropImages(from image: UIImage) {
        guard let ciImage = CIImage(image: image) else {
            print("Không thể chuyển UIImage thành CIImage")
            return
        }

        // Tạo request phát hiện hình chữ nhật
        let rectangleDetectionRequest = VNDetectRectanglesRequest { [weak self] request, error in
            if let error = error {
                print("Lỗi khi phát hiện hình chữ nhật: \(error)")
                return
            }

            guard let results = request.results as? [VNRectangleObservation] else {
                print("Không có kết quả phát hiện")
                return
            }

            print("Tìm thấy \(results.count) hình chữ nhật")

            guard let resultsSort = self?.sortRectanglesByPosition(results) else {
                print("Không có kết quả phát hiện")
                return
            }

            // Chuyển các boundingBox thành CGRect
            let rectangles = resultsSort.map { self?.convertBoundingBox($0.boundingBox, imageSize: image.size) ?? CGRect.zero }

            let filteredRectangles = self?.filterOverlappingRectangles(rectangles: rectangles) ?? []

            // Vẽ hình chữ nhật lên ảnh
            DispatchQueue.main.async {
                self?.drawRectangles(on: image, rectangles: filteredRectangles)
            }

            // Lấy từng phần ảnh từ các khung chữ nhật
            self?.croppedImages = self?.cropImages(from: image, rectangles: filteredRectangles) ?? []

            print("Số lượng ảnh con: \(self?.croppedImages.count ?? 0)")

            self?.clv.reloadData()
        }

        // Điều chỉnh các thông số quan trọng
        rectangleDetectionRequest.minimumAspectRatio = 0.5 // Cho phép tỷ lệ dài/rộng tối thiểu (hỗ trợ hình vuông dài).
        rectangleDetectionRequest.maximumAspectRatio = 2.0 // Tỷ lệ dài/rộng tối đa.
        rectangleDetectionRequest.minimumSize = 0.1 // Kích thước tối thiểu của hình chữ nhật so với ảnh.
        rectangleDetectionRequest.quadratureTolerance = 15 // Độ nghiêng tối đa cho phép (45 độ).
        rectangleDetectionRequest.maximumObservations = 20 // Số lượng hình chữ nhật tối đa được phát hiện.
        rectangleDetectionRequest.minimumConfidence = 0.5 // Confidence tối thiểu

        // Thực hiện request
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        do {
            try handler.perform([rectangleDetectionRequest])
        } catch {
            print("Lỗi khi thực hiện request: \(error)")
        }
    }

    // Chuyển boundingBox từ Vision thành CGRect trên ảnh gốc
    func convertBoundingBox(_ boundingBox: CGRect, imageSize: CGSize) -> CGRect {
        let width = boundingBox.width * imageSize.width
        let height = boundingBox.height * imageSize.height
        let x = boundingBox.origin.x * imageSize.width
        let y = (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    func cropImages(from image: UIImage, rectangles: [CGRect]) -> [UIImage] {
        var croppedImages: [UIImage] = []

        guard let cgImage = image.cgImage else { return [] }

        for rect in rectangles {
            // Chuyển CGRect thành CGRect thực tế dựa trên kích thước ảnh gốc
            let scaleFactor = image.size.width / CGFloat(cgImage.width)
            let scaledRect = CGRect(
                x: rect.origin.x / scaleFactor,
                y: rect.origin.y / scaleFactor,
                width: rect.size.width / scaleFactor,
                height: rect.size.height / scaleFactor
            )

            // Crop phần ảnh
            if let croppedCGImage = cgImage.cropping(to: scaledRect) {
                let croppedImage = UIImage(cgImage: croppedCGImage)
                croppedImages.append(croppedImage)
            }
        }

        return croppedImages
    }

    // MARK: - Draw Rectangles

    // Vẽ các hình chữ nhật lên ảnh
    func drawRectangles(on image: UIImage, rectangles: [CGRect]) {
        UIGraphicsBeginImageContext(image.size)
        let context = UIGraphicsGetCurrentContext()
        image.draw(at: .zero)

        context?.setStrokeColor(UIColor.red.cgColor)
        context?.setLineWidth(5.0)

        for rect in rectangles {
            context?.stroke(rect)
        }

        let updatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        // Hiển thị ảnh đã được thêm các hình chữ nhật
        self.imageTest.image = updatedImage
    }

    func filterOverlappingRectangles(rectangles: [CGRect]) -> [CGRect] {
        // Mảng giữ lại các hình chữ nhật sau khi lọc
        var filteredRectangles = rectangles

        // Duyệt qua từng cặp hình chữ nhật
        for i in 0..<filteredRectangles.count {
            for j in (i + 1)..<filteredRectangles.count {
                let rect1 = filteredRectangles[i]
                let rect2 = filteredRectangles[j]

                // Kiểm tra nếu hai hình chữ nhật giao nhau
                if rect1.intersects(rect2) {
                    // Tính diện tích của cả hai hình
                    let area1 = rect1.width * rect1.height
                    let area2 = rect2.width * rect2.height

                    // Loại bỏ hình nhỏ hơn
                    if area1 > area2 {
                        filteredRectangles[j] = .zero // Đánh dấu để xóa sau
                    } else {
                        filteredRectangles[i] = .zero // Đánh dấu để xóa sau
                    }
                }
            }
        }

        // Loại bỏ các hình chữ nhật bị đánh dấu là `.zero`
        filteredRectangles = filteredRectangles.filter { $0 != .zero }

        return filteredRectangles
    }

    func sortRectanglesByPosition(_ rectangles: [VNRectangleObservation]) -> [VNRectangleObservation] {
        return rectangles.sorted { rect1, rect2 in
            // Sắp xếp theo hàng (trục y từ trên xuống dưới)
            if abs(rect1.topLeft.y - rect2.topLeft.y) > 0.1 {
                return rect1.topLeft.y > rect2.topLeft.y
            }
            // Nếu cùng hàng, sắp xếp theo cột (trục x từ trái sang phải)
            if abs(rect1.topLeft.x - rect2.topLeft.x) > 0.1 {
                return rect1.topLeft.x < rect2.topLeft.x
            }
            // Nếu cùng vị trí, ưu tiên hình lớn hơn
            let area1 = calculateArea(of: rect1)
            let area2 = calculateArea(of: rect2)
            return area1 > area2
        }
    }

    func calculateArea(of rect: VNRectangleObservation) -> CGFloat {
        let width = hypot(rect.topLeft.x - rect.topRight.x, rect.topLeft.y - rect.topRight.y)
        let height = hypot(rect.topLeft.x - rect.bottomLeft.x, rect.topLeft.y - rect.bottomLeft.y)
        return width * height
    }

    func straightenRectangle(_ rectangle: VNRectangleObservation, in image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let ciImage = CIImage(cgImage: cgImage)

        // Tọa độ 4 góc từ VNRectangleObservation
        let topLeft = rectangle.topLeft
        let topRight = rectangle.topRight
        let bottomLeft = rectangle.bottomLeft
        let bottomRight = rectangle.bottomRight

        // Kích thước ảnh gốc
        let width = ciImage.extent.width
        let height = ciImage.extent.height

        // Tạo CIImage để thực hiện warp
        let perspectiveCorrection = CIFilter(name: "CIPerspectiveCorrection")!
        perspectiveCorrection.setValue(ciImage, forKey: kCIInputImageKey)

        perspectiveCorrection.setValue(CIVector(x: topLeft.x * width, y: (1 - topLeft.y) * height), forKey: "inputTopLeft")
        perspectiveCorrection.setValue(CIVector(x: topRight.x * width, y: (1 - topRight.y) * height), forKey: "inputTopRight")
        perspectiveCorrection.setValue(CIVector(x: bottomLeft.x * width, y: (1 - bottomLeft.y) * height), forKey: "inputBottomLeft")
        perspectiveCorrection.setValue(CIVector(x: bottomRight.x * width, y: (1 - bottomRight.y) * height), forKey: "inputBottomRight")

        guard let outputImage = perspectiveCorrection.outputImage else { return nil }

        // Tạo ảnh mới từ kết quả
        let context = CIContext()
        guard let correctedCGImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }
        return UIImage(cgImage: correctedCGImage)
    }

    // remove BG
    func convertImageToRedContent(image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Vẽ ảnh gốc lên context
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Duyệt qua từng pixel
        for y in 0..<height {
            for x in 0..<width {
                let byteIndex = (y * bytesPerRow) + (x * bytesPerPixel)

                let red = rawData[byteIndex]
                let green = rawData[byteIndex + 1]
                let blue = rawData[byteIndex + 2]
                let alpha = rawData[byteIndex + 3]

                // Nếu pixel có nội dung (không phải nền đen), chuyển thành đỏ
                if red > 10 || green > 10 || blue > 10 {
                    rawData[byteIndex] = 255 // Red
                    rawData[byteIndex + 1] = 0 // Green
                    rawData[byteIndex + 2] = 0 // Blue
                    rawData[byteIndex + 3] = alpha // Giữ nguyên alpha
                } else {
                    // Nếu là nền (đen), chuyển thành trắng
                    rawData[byteIndex] = 255 // Red
                    rawData[byteIndex + 1] = 255 // Green
                    rawData[byteIndex + 2] = 255 // Blue
                    rawData[byteIndex + 3] = alpha // Giữ nguyên alpha
                }
            }
        }

        // Tạo ảnh mới từ dữ liệu pixel đã xử lý
        let outputCGImage = context.makeImage()
        return outputCGImage.map { UIImage(cgImage: $0) }
    }

    func convertToBlackAndWhite(_ image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }

        // Áp dụng bộ lọc chuyển đổi ảnh thành grayscale
        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(0.0, forKey: kCIInputSaturationKey) // Chuyển thành grayscale
        filter?.setValue(1.0, forKey: kCIInputContrastKey)

        // Áp dụng ngưỡng nhị phân để giữ lại các chi tiết quan trọng
        let thresholdFilter = CIFilter(name: "CIColorThreshold") // Custom filter
        thresholdFilter?.setValue(filter?.outputImage, forKey: kCIInputImageKey)
        thresholdFilter?.setValue(0.7, forKey: "inputThreshold") // Điều chỉnh ngưỡng

        guard let outputImage = thresholdFilter?.outputImage else { return nil }
        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    func removeBackground(from image: UIImage, completion: @escaping (UIImage?) -> Void) {
        guard let cgImage = image.cgImage else {
            print("Không thể tạo CGImage từ UIImage.")
            completion(nil)
            return
        }

        // Resize ảnh nếu cần thiết
        let resizedImage = image.resize(to: CGSize(width: 512, height: 512))
        guard let resizedCgImage = resizedImage.cgImage else {
            print("Không thể resize ảnh.")
            completion(nil)
            return
        }

        // Tạo request phân đoạn người
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let requestHandler = VNImageRequestHandler(cgImage: resizedCgImage, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Thực hiện request
                try requestHandler.perform([request])

                // Kiểm tra kết quả
                guard let pixelBuffer = request.results?.first?.pixelBuffer else {
                    print("Không tìm thấy kết quả PixelBuffer.")
                    completion(nil)
                    return
                }

                // Chuyển đổi PixelBuffer thành UIImage
                guard let maskImage = UIImage(pixelBuffer: pixelBuffer) else {
                    print("Không thể chuyển đổi PixelBuffer thành UIImage.")
                    completion(nil)
                    return
                }

                // Áp dụng mask lên ảnh gốc
                let resultImage = resizedImage.applyMask(maskImage: maskImage)
                DispatchQueue.main.async {
                    completion(resultImage)
                }
            } catch {
                print("Lỗi khi thực hiện Vision Request: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}

extension ViewController: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.croppedImages.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(with: CellTextImage.self, for: indexPath)
        cell.imv.image = self.croppedImages[indexPath.row]
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 8
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 8
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: 100, height: 100)
    }
}

extension UIImage {
    func convertToRGB() -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: cgImage.width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard let newCGImage = context.makeImage() else { return nil }
        return UIImage(cgImage: newCGImage)
    }

    convenience init?(pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        self.init(cgImage: cgImage)
    }

    func applyMask(maskImage: UIImage?) -> UIImage? {
        guard let maskImage = maskImage else {
            print("Mask image không tồn tại.")
            return nil
        }
        guard let maskCgImage = maskImage.cgImage else {
            print("Không thể lấy CGImage từ mask.")
            return nil
        }
        guard let originalCgImage = self.cgImage else {
            print("Không thể lấy CGImage từ ảnh gốc.")
            return nil
        }

        let width = size.width
        let height = size.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // Tạo context
        guard let context = CGContext(
            data: nil,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("Không thể tạo CGContext.")
            return nil
        }

        // Vẽ ảnh gốc
        context.draw(originalCgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Áp dụng mask
        context.clip(to: CGRect(x: 0, y: 0, width: width, height: height), mask: maskCgImage)
        context.setFillColor(UIColor.clear.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Tạo ảnh kết quả
        guard let maskedCgImage = context.makeImage() else {
            print("Không thể tạo ảnh đã mask.")
            return nil
        }
        return UIImage(cgImage: maskedCgImage)
    }

    func resize(to size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resizedImage ?? self
    }

    func toCVPixelBuffer() -> CVPixelBuffer? {
        let width = Int(self.size.width)
        let height = Int(self.size.height)

        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary

        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         kCVPixelFormatType_32ARGB,
                                         attributes,
                                         &pixelBuffer)

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

        guard let cgImage = self.cgImage else { return nil }
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)

        return buffer
    }

    func crop(to: CGSize) -> UIImage {
        guard let cgimage = self.cgImage else { return self }

        let contextImage = UIImage(cgImage: cgimage)

        guard let newCgImage = contextImage.cgImage else { return self }

        let contextSize: CGSize = contextImage.size

        // Set to square
        var posX: CGFloat = 0.0
        var posY: CGFloat = 0.0
        let cropAspect: CGFloat = to.width / to.height

        var cropWidth: CGFloat = to.width
        var cropHeight: CGFloat = to.height

        if to.width > to.height { // Landscape
            cropWidth = contextSize.width
            cropHeight = contextSize.width / cropAspect
            posY = (contextSize.height - cropHeight) / 2
        } else if to.width < to.height { // Portrait
            cropHeight = contextSize.height
            cropWidth = contextSize.height * cropAspect
            posX = (contextSize.width - cropWidth) / 2
        } else { // Square
            if contextSize.width >= contextSize.height { // Square on landscape (or square)
                cropHeight = contextSize.height
                cropWidth = contextSize.height * cropAspect
                posX = (contextSize.width - cropWidth) / 2
            } else { // Square on portrait
                cropWidth = contextSize.width
                cropHeight = contextSize.width / cropAspect
                posY = (contextSize.height - cropHeight) / 2
            }
        }

        let rect = CGRect(x: posX, y: posY, width: cropWidth, height: cropHeight)

        // Create bitmap image from context using the rect
        guard let imageRef: CGImage = newCgImage.cropping(to: rect) else { return self }

        // Create a new image based on the imageRef and rotate back to the original orientation
        let cropped = UIImage(cgImage: imageRef, scale: self.scale, orientation: self.imageOrientation)

        UIGraphicsBeginImageContextWithOptions(to, false, self.scale)
        cropped.draw(in: CGRect(x: 0, y: 0, width: to.width, height: to.height))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resized ?? self
    }
}

extension MLMultiArray {
    func toUIImage() -> UIImage? {
        guard self.shape.count == 3 else {
            print("Output không phải 3 chiều.")
            return nil
        }

        let pointer = self.dataPointer.bindMemory(to: Float32.self, capacity: self.count)
        let array = Array(UnsafeBufferPointer(start: pointer, count: self.count))

        let width = self.shape[2].intValue
        let height = self.shape[1].intValue

        guard width > 0, height > 0 else {
            print("Kích thước output không hợp lệ.")
            return nil
        }

        let byteArray = array.map { UInt8(clamping: Int($0 * 255)) }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo: CGBitmapInfo = []
        guard let data = CFDataCreate(nil, byteArray, byteArray.count) else { return nil }
        guard let provider = CGDataProvider(data: data) else { return nil }
        guard let cgImage = CGImage(width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bitsPerPixel: 8,
                                    bytesPerRow: width,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo,
                                    provider: provider,
                                    decode: nil,
                                    shouldInterpolate: false,
                                    intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
