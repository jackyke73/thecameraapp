# Review: ZSON GuidanceOverlay Prototype

## Findings
1. **Hardcoded Target:** The target is currently static (`let targetLabel: String = "person"`).
   - *Action:* Expose a binding or injection point for dynamic target labels (e.g., from user voice/text input).

2. **Coordinate System Risks:**
   - The code manually inverts Y coordinates: `y: frameSize.height - rect.maxY`.
   - *Issue:* This assumes the `frameSize` matches the Vision buffer's aspect ratio perfectly. If the camera preview is "Aspect Fill" (zoomed/cropped), these boxes will drift.
   - *Fix:* Use `AVLayerVideoGravity` logic or `PreviewLayer` coordinate conversion if possible, or ensure the Vision request runs on a cropped buffer matching the screen.

3. **Arrow Logic:**
   - `DirectionalArrowView` calculates vectors based on normalized coordinates.
   - *Issue:* It doesn't clamp the arrow to the screen edge. It draws it at the center.
   - *Improvement:* For off-screen targets (if we add 360° awareness later), the arrow should stick to the edge of the screen pointing towards the target. For on-screen targets, a center arrow is okay but maybe redundant if the box is visible.

4. **Performance:**
   - `ForEach(observations)` in `ZStack` is generally fine for <10 objects.
   - *Optimization:* Filter observations *before* passing to the view if the list gets long (e.g., 100+ items).

## Next Steps
- [ ] Refactor `targetLabel` to be an injected parameter.
- [ ] Implement edge-clamping for the directional arrow (so it guides you even if the object is *just* outside the frame).
- [ ] Verify coordinate transform on actual device (Simulator camera is tricky).
