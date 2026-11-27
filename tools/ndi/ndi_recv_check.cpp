// Independent NDI receiver for the check: finds the sources on the network, connects to the first one whose name
// contains the given text, counts the video frames received for N seconds, and saves one frame as a PPM image.
// Build: g++ -O2 -I"$NDI_SDK_DIR/include" ndi_recv_check.cpp -o ndi_recv_check -ldl   (NDI_SDK_DIR: the unpacked SDK)
// Run:   ./ndi_recv_check <engine>/Engine/Plugins/Media/NDIMedia/Binaries/ThirdParty/LinuxArm64/libndi.so.6 SparkUE 20 frame.ppm
// Prints the sources it sees, then one JSON line: frames, resolution, declared and measured fps.
#include <Processing.NDI.Lib.h>
#include <dlfcn.h>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

int main(int argc, char** argv) {
    if (argc < 4) { std::fprintf(stderr, "usage: %s LIBNDI NAME_SUBSTRING SECONDS [OUT.ppm]\n", argv[0]); return 2; }
    void* h = dlopen(argv[1], RTLD_NOW);
    if (!h) { std::fprintf(stderr, "dlopen: %s\n", dlerror()); return 1; }
    auto load = reinterpret_cast<const NDIlib_v6* (*)()>(dlsym(h, "NDIlib_v6_load"));
    const NDIlib_v6* ndi = load ? load() : nullptr;
    if (!ndi || !ndi->initialize()) { std::fprintf(stderr, "NDI init failed\n"); return 1; }
    std::printf("NDI %s\n", ndi->version());

    NDIlib_find_instance_t find = ndi->find_create_v2(nullptr);
    const NDIlib_source_t* srcs = nullptr; uint32_t n = 0; int pick = -1;
    for (int t = 0; t < 30 && pick < 0; ++t) {
        ndi->find_wait_for_sources(find, 1000);
        srcs = ndi->find_get_current_sources(find, &n);
        for (uint32_t i = 0; i < n; ++i) {
            if (t == 0 || pick < 0) std::printf("source: %s\n", srcs[i].p_ndi_name);
            if (std::strstr(srcs[i].p_ndi_name, argv[2])) { pick = int(i); break; }
        }
    }
    if (pick < 0) { std::printf("no source matching '%s'\n", argv[2]); return 1; }
    std::printf("connecting to: %s\n", srcs[pick].p_ndi_name);

    NDIlib_recv_create_v3_t rc = {};
    rc.source_to_connect_to = srcs[pick];
    rc.color_format = NDIlib_recv_color_format_BGRX_BGRA;
    rc.bandwidth = NDIlib_recv_bandwidth_highest;
    NDIlib_recv_instance_t recv = ndi->recv_create_v3(&rc);
    ndi->find_destroy(find);

    const double secs = std::atof(argv[3]);
    int frames = 0, w = 0, hgt = 0, fn = 0, fd = 0; bool saved = argc < 5;
    auto t0 = std::chrono::steady_clock::now(); double first = -1, last = 0;
    while (std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count() < secs) {
        NDIlib_video_frame_v2_t v;
        if (ndi->recv_capture_v3(recv, &v, nullptr, nullptr, 1000) == NDIlib_frame_type_video) {
            double now = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
            if (first < 0) first = now;
            last = now; ++frames; w = v.xres; hgt = v.yres; fn = v.frame_rate_N; fd = v.frame_rate_D;
            if (!saved && frames == 30) {
                FILE* f = std::fopen(argv[4], "wb");
                std::fprintf(f, "P6\n%d %d\n255\n", v.xres, v.yres);
                for (int y = 0; y < v.yres; ++y) {
                    const uint8_t* row = v.p_data + y * v.line_stride_in_bytes;
                    for (int x = 0; x < v.xres; ++x) { uint8_t rgb[3] = {row[4 * x + 2], row[4 * x + 1], row[4 * x]}; std::fwrite(rgb, 1, 3, f); }
                }
                std::fclose(f); saved = true;
            }
            ndi->recv_free_video_v2(recv, &v);
        }
    }
    double span = last - first;
    std::printf("{\"frames\": %d, \"xres\": %d, \"yres\": %d, \"declared_fps\": %.2f, \"received_fps\": %.2f, \"seconds\": %.1f}\n",
                frames, w, hgt, fd ? double(fn) / fd : 0.0, frames > 1 && span > 0 ? (frames - 1) / span : 0.0, span);
    ndi->recv_destroy(recv);
    ndi->destroy();
    return frames > 0 ? 0 : 1;
}
