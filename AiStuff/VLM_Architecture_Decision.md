# Decision: VLM Architecture for SmolVLM-256M

## Recommendation: CoreML (Primary) with ExecuTorch Fallback

### Rationale
1.  **Hardware Efficiency (ANE):** For a model as small as 256M parameters, the primary goal is **extreme power efficiency** and **low latency** to allow always-on usage (e.g., real-time scene analysis). CoreML is the only path to fully utilize the Apple Neural Engine (ANE), which is crucial for battery life. ExecuTorch primarily targets the GPU (via MPS) or CPU, which is less efficient for continuous background tasks.
2.  **Model Size:** 256M parameters is tiny. Even without heavy quantization, it fits easily in RAM. The overhead of the ExecuTorch runtime (library size) might be larger than the marginal gain in flexibility. CoreML runtime is built-in to iOS.
3.  **Integration:** CoreML integrates seamlessly with Vision (VNCoreMLRequest) and SwiftUI. ExecuTorch requires a C++ bridge and manual buffer management.

### Strategy
1.  **Attempt CoreML Conversion:** Use `coremltools` to convert the SmolVLM-256M components:
    *   **Vision Encoder:** Convert to float16 CoreML (likely fits on ANE).
    *   **LLM/Transformer:** Convert to `int4` or `int8` palletized CoreML using `coremltools.optimize.coreml`.
    *   *Success Metric:* If the model compiles and runs on ANE with <50ms latency for the encoder.

2.  **Fallback to ExecuTorch (MPS):** If `coremltools` fails due to unsupported operations (e.g., specific attention masks or RoPE implementations in the new model architecture):
    *   Use ExecuTorch with the MPS (Metal Performance Shaders) backend.
    *   This will run on the GPU, which is fast but more power-hungry than ANE.

### Selected Path: CoreML
We will proceed with **CoreML** as the target. The 256M model is small enough that we should prioritize the ANE for "always-on" capabilities.

## Next Steps
- [ ] Locate the SmolVLM-256M PyTorch weights (HuggingFace).
- [ ] Create a Python script to run `coremltools` conversion.
- [ ] Validate layers on ANE using XCode Instruments.
