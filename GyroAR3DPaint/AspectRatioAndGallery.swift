import SwiftUI
import Photos
import UIKit
import AVFoundation

// MARK: - Aspect Ratio
enum AspectRatioMode: String, CaseIterable {
    case ratio16_9 = "16:9"
    case ratio4_3 = "4:3"
    case ratio1_1 = "1:1"
    
    var ratio: CGFloat {
        switch self {
        case .ratio16_9: return 16.0 / 9.0
        case .ratio4_3: return 4.0 / 3.0
        case .ratio1_1: return 1.0
        }
    }
    
    var icon: String {
        switch self {
        case .ratio16_9: return "rectangle.portrait"
        case .ratio4_3: return "rectangle.portrait.fill"
        case .ratio1_1: return "square"
        }
    }
}

// MARK: - Canvas Frame Calculator
struct CanvasFrame {
    let screenSize: CGSize
    let aspectMode: AspectRatioMode
    let topMargin: CGFloat
    let bottomMargin: CGFloat
    
    var canvasRect: CGRect {
        let availableHeight = screenSize.height - topMargin - bottomMargin
        let availableWidth = screenSize.width
        let targetRatio = aspectMode.ratio
        var canvasWidth: CGFloat
        var canvasHeight: CGFloat
        
        if availableWidth / availableHeight > (1 / targetRatio) {
            canvasHeight = availableHeight
            canvasWidth = canvasHeight / targetRatio
        } else {
            canvasWidth = availableWidth
            canvasHeight = canvasWidth * targetRatio
        }
        
        let x = (screenSize.width - canvasWidth) / 2
        let y = topMargin + (availableHeight - canvasHeight) / 2
        return CGRect(x: x, y: y, width: canvasWidth, height: canvasHeight)
    }
}

// MARK: - Canvas Overlay View
struct CanvasOverlayView: View {
    let aspectMode: AspectRatioMode
    let topMargin: CGFloat
    let bottomMargin: CGFloat
    
    var body: some View {
        GeometryReader { geo in
            let frame = CanvasFrame(screenSize: geo.size, aspectMode: aspectMode, topMargin: topMargin, bottomMargin: bottomMargin)
            let rect = frame.canvasRect
            
            Path { path in
                path.addRect(CGRect(origin: .zero, size: geo.size))
                path.addRect(rect)
            }
            .fill(Color.black.opacity(0.7), style: FillStyle(eoFill: true))
            
            Rectangle()
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Gallery Item
struct GalleryItem: Identifiable, Codable {
    let id: UUID
    let filename: String
    let createdAt: Date
    let isVideo: Bool
    let brushType: String
    let aspectRatio: String
    
    init(filename: String, isVideo: Bool, brushType: String, aspectRatio: String) {
        self.id = UUID()
        self.filename = filename
        self.createdAt = Date()
        self.isVideo = isVideo
        self.brushType = brushType
        self.aspectRatio = aspectRatio
    }
}

// MARK: - Gallery Manager
@MainActor
class GalleryManager: ObservableObject {
    @Published var items: [GalleryItem] = []
    private let fileManager = FileManager.default
    
    private var galleryURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Gallery", isDirectory: true)
    }
    private var metadataURL: URL { galleryURL.appendingPathComponent("metadata.json") }
    
    init() {
        try? fileManager.createDirectory(at: galleryURL, withIntermediateDirectories: true)
        loadMetadata()
    }
    
    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
              let loaded = try? JSONDecoder().decode([GalleryItem].self, from: data) else { return }
        items = loaded
    }
    
    private func saveMetadata() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: metadataURL)
    }
    
    func saveImage(_ image: UIImage, brushType: String, aspectRatio: String) -> URL? {
        let filename = "IMG_\(Int(Date().timeIntervalSince1970)).jpg"
        let url = galleryURL.appendingPathComponent(filename)
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        do {
            try data.write(to: url)
            let item = GalleryItem(filename: filename, isVideo: false, brushType: brushType, aspectRatio: aspectRatio)
            items.insert(item, at: 0)
            saveMetadata()
            return url
        } catch { return nil }
    }
    
    func getURL(for item: GalleryItem) -> URL { galleryURL.appendingPathComponent(item.filename) }
    
    func thumbnail(for item: GalleryItem) -> UIImage? {
        let url = getURL(for: item)
        if item.isVideo {
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                return UIImage(cgImage: cgImage)
            }
            return nil
        } else {
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
            return image
        }
    }
}

// MARK: - Gallery View
struct GalleryView: View {
    @ObservedObject var galleryManager: GalleryManager
    let onDismiss: () -> Void
    let onSelect: (GalleryItem) -> Void
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Gallery").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                Spacer()
                Text("\(galleryManager.items.count) items").font(.system(size: 12)).foregroundColor(.gray)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundColor(.gray)
                }
            }.padding().background(Color.black)
            
            if galleryManager.items.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 48)).foregroundColor(.gray)
                    Text("No captures yet").foregroundColor(.gray)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(galleryManager.items) { item in
                            GalleryItemView(item: item, galleryManager: galleryManager)
                                .onTapGesture { onSelect(item) }
                        }
                    }.padding(4)
                }
            }
        }.background(Color.black)
    }
}

struct GalleryItemView: View {
    let item: GalleryItem
    @ObservedObject var galleryManager: GalleryManager
    @State private var thumbnail: UIImage?
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let thumb = thumbnail {
                Image(uiImage: thumb).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100).clipped()
            } else {
                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 100, height: 100)
            }
            if item.isVideo {
                Image(systemName: "play.circle.fill").foregroundColor(.white).font(.system(size: 24))
                    .shadow(radius: 2).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(item.brushType).font(.system(size: 8)).foregroundColor(.white)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(Color.black.opacity(0.7)).cornerRadius(4).padding(4)
        }
        .onAppear { Task { thumbnail = galleryManager.thumbnail(for: item) } }
    }
}

// MARK: - Image Paint Source
@MainActor
class ImagePaintSource: ObservableObject {
    @Published var sourceImage: UIImage?
    @Published var cropRect: CGRect = .zero
    @Published var isActive = false
    
    private var pixelData: [UInt8] = []
    private var imageWidth: Int = 0
    private var imageHeight: Int = 0
    private var sampleIndex: Int = 0
    
    func setImage(_ image: UIImage, cropRect: CGRect? = nil) {
        sourceImage = image
        self.cropRect = cropRect ?? CGRect(origin: .zero, size: image.size)
        isActive = true
        preparePixelData()
    }
    
    private func preparePixelData() {
        guard let image = sourceImage, let cgImage = image.cgImage else { return }
        let cropCG = CGRect(
            x: cropRect.origin.x * CGFloat(cgImage.width) / (sourceImage?.size.width ?? 1),
            y: cropRect.origin.y * CGFloat(cgImage.height) / (sourceImage?.size.height ?? 1),
            width: cropRect.width * CGFloat(cgImage.width) / (sourceImage?.size.width ?? 1),
            height: cropRect.height * CGFloat(cgImage.height) / (sourceImage?.size.height ?? 1)
        )
        guard let croppedCG = cgImage.cropping(to: cropCG) else { return }
        imageWidth = croppedCG.width
        imageHeight = croppedCG.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * imageWidth
        pixelData = [UInt8](repeating: 0, count: imageWidth * imageHeight * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &pixelData, width: imageWidth, height: imageHeight,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.draw(croppedCG, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        sampleIndex = 0
    }
    
    func nextUIColor() -> UIColor {
        guard !pixelData.isEmpty, imageWidth > 0, imageHeight > 0 else { return .white }
        let totalPixels = imageWidth * imageHeight
        let pixelIndex = sampleIndex % totalPixels
        sampleIndex += 7
        let byteIndex = pixelIndex * 4
        guard byteIndex + 3 < pixelData.count else { return .white }
        let r = CGFloat(pixelData[byteIndex]) / 255.0
        let g = CGFloat(pixelData[byteIndex + 1]) / 255.0
        let b = CGFloat(pixelData[byteIndex + 2]) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }
    
    func clear() { sourceImage = nil; pixelData = []; isActive = false }
}

// MARK: - Image Crop View
struct ImageCropView: View {
    let image: UIImage
    @Binding var cropRect: CGRect
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @State private var dragOffset: CGSize = .zero
    @State private var cropSize: CGSize = CGSize(width: 100, height: 100)
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Select Paint Area").font(.headline).foregroundColor(.white)
                GeometryReader { geo in
                    let imageSize = calculateImageSize(in: geo.size)
                    let imageOrigin = CGPoint(x: (geo.size.width - imageSize.width) / 2, y: (geo.size.height - imageSize.height) / 2)
                    ZStack {
                        Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                            .frame(width: imageSize.width, height: imageSize.height)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        Rectangle().stroke(Color.yellow, lineWidth: 2).background(Color.white.opacity(0.2))
                            .frame(width: cropSize.width, height: cropSize.height)
                            .position(x: imageOrigin.x + cropSize.width / 2 + dragOffset.width,
                                      y: imageOrigin.y + cropSize.height / 2 + dragOffset.height)
                            .gesture(DragGesture().onChanged { dragOffset = $0.translation }
                                .onEnded { _ in
                                    let scale = image.size.width / imageSize.width
                                    cropRect = CGRect(x: dragOffset.width * scale, y: dragOffset.height * scale,
                                        width: cropSize.width * scale, height: cropSize.height * scale)
                                })
                    }
                }.frame(height: 300)
                HStack(spacing: 30) {
                    Button("Cancel") { onCancel() }.foregroundColor(.red)
                    Button("Use Full") { cropRect = CGRect(origin: .zero, size: image.size); onConfirm() }.foregroundColor(.white)
                    Button("Use Selection") { onConfirm() }.foregroundColor(.green)
                }
            }.padding()
        }
    }
    
    private func calculateImageSize(in containerSize: CGSize) -> CGSize {
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height
        if imageAspect > containerAspect {
            let width = containerSize.width
            return CGSize(width: width, height: width / imageAspect)
        } else {
            let height = containerSize.height
            return CGSize(width: height * imageAspect, height: height)
        }
    }
}
