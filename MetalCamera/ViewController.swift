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
    private var cancellables: Set<AnyCancellable> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(metalRenderingView)
        metalRenderingView.snp.makeConstraints {make in
            make.edges.equalToSuperview()
        }

        cameraService.videoOutputPublisher
            .map { CMSampleBufferGetImageBuffer($0) }
            .assign(to: \.pixelBuffer, on: metalRenderingView)
            .store(in: &cancellables)

        cameraService.start(with: .hd1920x1080)
    }
}
