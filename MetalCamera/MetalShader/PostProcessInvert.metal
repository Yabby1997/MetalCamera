//
//  PostProcessInvert.metal
//  MetalCamera
//
//  Created by USER on 2023/05/29.
//

#include <metal_stdlib>
using namespace metal;


[[kernel]]
void postProcessInvert(uint2 gid [[thread_position_in_grid]],
                       texture2d<half, access::read> inColor [[texture(0)]],
                       texture2d<half, access::write> outColor [[texture(1)]])
{
    if (gid.x >= inColor.get_width() || gid.y >= inColor.get_height()) {
        return;
    }

    outColor.write(1.0 - inColor.read(gid), gid);
}
