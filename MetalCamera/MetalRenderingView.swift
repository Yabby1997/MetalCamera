//
//  MetalRenderingView.swift
//  MetalCamera
//
//  Created by USER on 2023/05/29.
//

import MetalKit
import MetalPerformanceShaders
import SnapKit
import Combine

final class MetalRenderingView: UIView {
    // MARK: - Subviews

    private let metalView = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())

    // MARK: - Properties

    private var device: MTLDevice? { metalView.device }
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLComputePipelineState?
    private var textureCache: CVMetalTextureCache?
    private var scaleShader: MPSImageScale?
    private var cancellables: Set<AnyCancellable> = []
    @Published var pixelBuffer: CVPixelBuffer?

    // MARK: - Initializers

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupMetal()
    }

    required public init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setups

    private func setupViews() {
        metalView.layer.isOpaque = false
        addSubview(metalView)
        metalView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func setupMetal() {
        guard let device else { return }
        scaleShader = MPSImageLanczosScale(device: device)
        commandQueue = device.makeCommandQueue()

        metalView.framebufferOnly = false
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = true
        metalView.delegate = self

        guard CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            [kCVMetalTextureCacheMaximumTextureAgeKey: 0] as CFDictionary,
            device,
            nil,
            &textureCache
        ) == kCVReturnSuccess else {
            return
        }

        $pixelBuffer
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.metalView.setNeedsDisplay()
            }
            .store(in: &cancellables)
    }
}

// MARK: - MTKViewDelegate Implementation

extension MetalRenderingView: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let textureCache,
              let pixelBuffer,
              let commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let currentInputWidth = CVPixelBufferGetWidth(pixelBuffer)
        let currentInputHeight = CVPixelBufferGetHeight(pixelBuffer)
        var inputCvMetalTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            currentInputWidth,
            currentInputHeight,
            0,
            &inputCvMetalTexture
        )

        guard let scaleShader,
              let inputCvMetalTexture,
              let inputMetalTexture = CVMetalTextureGetTexture(inputCvMetalTexture),
              let currentDrawable = metalView.currentDrawable else { return }

        let textureScale = metalView.drawableSize.height / CGFloat(currentInputHeight)
        var transform = MPSScaleTransform(
            scaleX: textureScale,
            scaleY: textureScale,
            translateX: .zero,
            translateY: .zero
        )

        withUnsafePointer(to: &transform) { scaleShader.scaleTransform = $0 }
        scaleShader.encode(
            commandBuffer: commandBuffer,
            sourceTexture: inputMetalTexture,
            destinationTexture: currentDrawable.texture
        )
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
}
