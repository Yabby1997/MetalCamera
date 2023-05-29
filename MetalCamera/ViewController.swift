//
//  ViewController.swift
//  MetalCamera
//
//  Created by USER on 2023/05/29.
//

import UIKit
import AVKit
import Combine

class ViewController: UIViewController {

    private let cameraService = CameraService()
    private let metalRenderingView = MetalRenderingView()
    private let metalService = MetalService(resolution: CGSize(width: 1080, height: 1920))
    private var cancellables: Set<AnyCancellable> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(metalRenderingView)
        metalRenderingView.snp.makeConstraints {make in
            make.edges.equalToSuperview()
        }

        cameraService.videoOutputPublisher
            .sink { [weak self] pixelBuffer in
                self?.metalService.process(pixelBuffer: pixelBuffer)
            }
            .store(in: &cancellables)

        metalService.pixelBufferOutput
            .sink { [weak self] pixelBuffer in
                self?.metalRenderingView.process(pixelBuffer: pixelBuffer)
            }
            .store(in: &cancellables)

        cameraService.start(with: .hd1920x1080)
        metalService.setupMetal()
    }
}
