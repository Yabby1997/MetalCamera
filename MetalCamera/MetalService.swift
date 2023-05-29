//
//  MetalService.swift
//  MetalCamera
//
//  Created by USER on 2023/05/29.
//

import Foundation
import Metal
import CoreVideo
import Combine

final class MetalService {
    private let device = MTLCreateSystemDefaultDevice()
    private var commandQueue: MTLCommandQueue?
    private var textureCache: CVMetalTextureCache?
    private var pipeline: MTLComputePipelineState?
    private var cvPixelBufferPool: CVPixelBufferPool?
    private let resolution: CGSize

    @Published private var pixelBuffer: CVPixelBuffer?
    var pixelBufferOutput: AnyPublisher<CVPixelBuffer, Never> {
        $pixelBuffer.compactMap { $0 }.eraseToAnyPublisher()
    }

    init(resolution: CGSize) {
        self.resolution = resolution
        CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            [kCVPixelBufferPoolMinimumBufferCountKey: 4] as CFDictionary,
            [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: resolution.width,
                kCVPixelBufferHeightKey: resolution.height,
                kCVPixelFormatOpenGLESCompatibility: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:],
            ] as CFDictionary,
            &cvPixelBufferPool
        )
    }

    func setupMetal(function: String = "postProcessInvert") {
        guard let device else { return }
        commandQueue = device.makeCommandQueue()
        guard CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            [kCVMetalTextureCacheMaximumTextureAgeKey: 0] as CFDictionary,
            device,
            nil,
            &textureCache
        ) == kCVReturnSuccess else {
            return
        }

        do {
            let library = try device.makeDefaultLibrary(bundle: Bundle.main)
            if let invertKernel = library.makeFunction(name: function) {
                pipeline = try device.makeComputePipelineState(function: invertKernel)
            } else {
                fatalError("retrieving \(function) failed")
            }
        }
        catch {
            fatalError(error.localizedDescription)
        }
    }

    func process(pixelBuffer: CVPixelBuffer) {
        guard let device,
              let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let textureCache,
              let pipeline else { return }

        let inputWidth = CVPixelBufferGetWidth(pixelBuffer)
        let inputHeight = CVPixelBufferGetHeight(pixelBuffer)

        var inputCvMetalTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            inputWidth,
            inputHeight,
            0,
            &inputCvMetalTexture
        )

        guard let inputCvMetalTexture,
              let inputMetalTexture = CVMetalTextureGetTexture(inputCvMetalTexture) else { return }

        let outputTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(resolution.width),
            height: Int(resolution.height),
            mipmapped: false
        )
        outputTextureDescriptor.usage = [.shaderWrite, .shaderRead]
        guard let outputTexture = device.makeTexture(descriptor: outputTextureDescriptor),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(inputMetalTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: inputWidth / threadGroupSize.width,
            height: inputHeight / threadGroupSize.height,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()

        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            var newPixelBuffer: CVPixelBuffer?
            guard let pixelBufferPool = self.cvPixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(
                    kCFAllocatorDefault,
                    pixelBufferPool,
                    &newPixelBuffer
                  ) == kCVReturnSuccess,
                  let newPixelBuffer else { return }

            CVPixelBufferLockBaseAddress(newPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            guard let baseAddress = CVPixelBufferGetBaseAddress(newPixelBuffer) else { return }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(newPixelBuffer)

            outputTexture.getBytes(
                baseAddress,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, outputTexture.width, outputTexture.height),
                mipmapLevel: 0
            )
            self.pixelBuffer = newPixelBuffer
            CVPixelBufferUnlockBaseAddress(newPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        }

        commandBuffer.commit()
    }
}
