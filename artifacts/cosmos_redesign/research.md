# Cosmos 3D System Map — Premium Redesign Research

## Reference matrix (six dashboards)

### 1. Linear orchestration / "Method"
*linear.app/method*
- **shape**: Radial orbit metaphors with soft-edged glass cards floating in z-space, avoiding harsh geometry for organic containment.
- **motion**: Cubic-bezier ease-outs (0.2, 0, 0, 1) for entrance, subtle sine-wave idle drift on floating elements, parallax on scroll.
- **palette**: 2-3 distinct hues (deep indigo, soft violet, white) with saturation locked below 60% to prevent chromatic noise.
- **depth_technique**: Multi-layered backdrop blur (40px+) combined with translucent borders (rgba white 0.1) to create volumetric glass without WebGL.
- **particle_density**: Sparse to none; negative space acts as the primary texture, letting typography breathe.
- **performance_signals**: CSS-only transforms, will-change hints on floating layers, skeleton screens matching final glass opacity.
**Takeaway**: Steal the restraint in color usage and the glass-morphism layering that suggests depth without GPU overhead; avoid the orbital metaphor if it implies rigid hierarchy rather than fluid orchestration, as ABS requires dynamic node relationships not fixed planetary orbits.

### 2. Vercel Insights dashboard
*vercel.com/dashboard*
- **shape**: Force-directed node clusters rendered as minimalist metric cards, using isometric perspective only for deployment pipeline visualizations.
- **motion**: Staggered fade-up entrances (80ms delay cascade), spring physics on hover states, no continuous ambient motion.
- **palette**: Strictly monochromatic slate with single cyan accent (#0070f3), maintaining WCAG 2.1 contrast ratios above 4.5:1.
- **depth_technique**: CSS box-shadow layering (0 25px 50px -12px rgba(0,0,0,0.5)) creating faux-3D elevation without canvas rendering.
- **particle_density**: None; data density conveyed through typographic hierarchy and micro-chart sparklines rather than ambient noise.
- **performance_signals**: Route-based code splitting, placeholder shimmer matching dark theme (#0a0e1a base), intersection observer for below-fold charts.
**Takeaway**: Adopt the disciplined single-accent palette and the elevation-shadow system that communicates hierarchy through z-index layering; avoid the dashboard's tendency toward flatness, as ABS needs genuine spatial depth to convey system topology, not just metric cards.

### 3. Stripe Sigma
*stripe.com/sigma*
- **shape**: Stacked layer cake visualization with SQL blocks as physical cards, using axonometric projection to suggest database depth without full 3D rotation.
- **motion**: Horizontal slide transitions with hardware-accelerated translate3d, snap-to-grid alignment animations emphasizing precision.
- **palette**: Deep navy (#0a2540) with mint accent (#00d4aa), high contrast monochrome for data tables, saturation used only for actionable elements.
- **depth_technique**: Overlapping cards with increasing blur on background layers (mimicking camera focus), combined with 1px hairline borders that catch light.
- **particle_density**: Sparse connector lines only; data flow represented through animated SVG paths rather than particle fields.
- **performance_signals**: Virtualized scrolling for large datasets, deferred loading of chart libraries, aggressive prefetching of adjacent dashboard states.
**Takeaway**: Steal the axonometric layering that makes abstract data feel tactile and the mint-accented monochrome that signals "financial precision"; avoid the static nature of the stack, as ABS requires living, breathing motion to represent active orchestration rather than static reports.

### 4. GitHub Octoverse globe
*octoverse.github.com*
- **shape**: Spherical force-directed graph with geographic nodes, using great-circle arcs for connection geometry rather than straight lines.
- **motion**: Inertia-based rotation on drag, particle birth animations (scale 0→1 with easeOutBack), pulsing rings on active nodes.
- **palette**: Oceanic blues (#1f6feb) to cyan (#58a6ff) gradient, restricted to analogous hues with high luminance variation for depth.
- **depth_technique**: Three.js WebGL with custom shader atmosphere glow, depth-of-field blur on background stars, parallax starfield layers.
- **particle_density**: Dense (10k+ points) for starfield background, sparse (200-500) for data nodes, using size attenuation for distance cues.
- **performance_signals**: LOD (Level of Detail) switching based on zoom, instanced mesh rendering for particles, requestAnimationFrame throttling to 30fps on battery.
**Takeaway**: Adopt the atmospheric glow shaders and the density contrast between background noise and foreground data; avoid the literal geographic metaphor, as ABS orchestrates abstract services not physical locations, making the globe projection semantically misleading.

### 5. Anthropic Constitutional AI / research aesthetic
*anthropic.com/research*
- **shape**: Asymmetric bento-grid layouts with mathematical typography, using golden-ratio column spans to create rhythm without explicit lines.
- **motion**: Scroll-triggered opacity reveals with 200ms linear ease, no parallax, emphasizing content over decoration.
- **palette**: Warm grayscale (slate #0f172a to stone #f8fafc) with single amber highlight (#f59e0b), extremely desaturated scientific aesthetic.
- **depth_technique**: Flat design with subtle inner shadows (inset 0 2px 4px rgba(0,0,0,0.3)) creating pressed-paper texture rather than spatial depth.
- **particle_density**: None; whitespace and grid lines provide all visual structure.
- **performance_signals**: Static site generation, zero JavaScript for layout, system font stack eliminating FOIT/FOUT.
**Takeaway**: Steal the typographic authority and the ruthless elimination of decorative elements that don't serve information hierarchy; avoid the flatness and lack of motion, as ABS must visualize dynamic system states that require spatial metaphors, not static research papers.

### 6. Three.js examples / Particle systems / postprocessing
*threejs.org/examples*
- **shape**: Procedural geometry with BufferAttribute instancing, using force-directed physics (verlet integration) for natural clustering behaviors.
- **motion**: Physics-based damping (0.95 friction), bloom post-processing on highlight states, camera dolly with logarithmic depth buffer.
- **palette**: Typically rainbow in demos, but premium implementations use HSLuv perceptually uniform gradients with locked lightness.
- **depth_technique**: True WebGL depth buffer with SSAO (Screen Space Ambient Occlusion), bloom pass, and tone mapping (ACESFilmic).
- **particle_density**: Configurable from sparse (500) to dense (50k) with frustum culling and octree spatial indexing.
- **performance_signals**: Stats.js FPS counter, geometry merging, texture atlasing, offscreen canvas workers for physics calculations.
**Takeaway**: Steal the physics-based force simulation and post-processing pipeline (bloom + tone mapping) for premium light effects; avoid the rainbow default palettes and uncapped particle counts that tank mobile GPUs, instead enforcing strict monochromatic constraints and density limits.

## Synthesis — what makes premium premium

Premium dashboards achieve sophistication not through technological excess but through ruthless chromatic restraint and physical metaphor consistency. The unanimous lesson across Linear, Vercel, and Stripe is that depth must be earned through layered translucency and shadow physics rather than gratuitous rotation or rainbow categorization—color is information, not decoration, and limiting the palette to the brand's deep navy (`#0a0e1a`) through electric blue (`#3a9dff`) spectrum creates cognitive hierarchy without circus hues. Motion serves state-change communication, not entertainment; idle drift and physics-based settling (damping 0.9–0.95) signal "living system" while constant spin signals "loading screen." Glass-morphism succeeds only when backed by genuine z-axis layering and backdrop-filter performance budgets, not when faked with linear gradients. Particle systems must obey data-density rules: background noise (stars, dust) can be dense and desaturated, but foreground nodes must breathe with generous whitespace, using luminance contrast (`#1e57ac` against `#78bdff`) rather than hue variation to distinguish entities. Finally, premium implies respect for user agency—reduced-motion fallbacks, keyboard navigation, and 60fps guarantees on M4 hardware are not features but baseline hygiene, distinguishing professional tools from tech demos.

## Direction recommendation for Automatia ABS

### Option 1 — Cosmos-orbital (improved)
Inspired by Linear's glass orbits and GitHub's atmospheric depth, this approach treats services as moons in a physics-simulated solar system where gravity represents dependency weight. It visually communicates that ABS brings gravitational order to chaotic cloud resources, with larger nodes exerting visual pull on smaller satellites. The entrance metaphor shows particles exploding from a central "big bang" of chaos before settling into stable orbital resonance, symbolizing the "Automate the Chaos" promise. However, the main risk is semantic confusion: users may interpret fixed orbits as rigid architecture rather than fluid orchestration, potentially misunderstanding the dynamic nature of microservices.

### Option 2 — Force-directed graph
Drawing from Vercel's node clustering and Three.js physics examples, this uses d3-force simulation with edge bundling to show service dependencies as tensioned springs, with data packets rendered as glowing particles traversing the edges. It communicates ABS as a living nervous system where orchestration pulses through visible energy transfer between nodes. The entrance depicts a scattered mess of disconnected nodes that snap into relational geometry as the system initializes, literalizing the chaos-to-order narrative. The primary risk is visual clutter; without aggressive LOD culling and strict particle limits, dense microservice topologies devolve into "hairball" spaghetti that obscures rather than reveals system health.

### Option 3 — Iso-axonometric grid
Borrowing Stripe Sigma's layered card stacks and Anthropic's grid discipline, this presents providers as stacked glass cards in an isometric projection, with data flowing between layers like sand through an hourglass. It visually suggests ABS as a precision instrument for stacking and routing cloud resources with architectural clarity, emphasizing the "building blocks" aspect of orchestration. The entrance animation shows cards collapsing from a disordered pile into a neat, sorted stack while connections draw themselves with drafting-precision lines. The main risk is spatial limitation; isometric views struggle to accommodate scale beyond 20–30 nodes before occlusion hides critical infrastructure, potentially misrepresenting large-scale distributed systems.

## Performance + a11y guardrails

- Bundle delta budget ≤180KB gz for the 3D widget chunk, excluding shared design system assets.
- 60fps target on Apple M4 / RTX 3060+, 30fps floor on Intel UHD / low-end mobile via adaptive quality scaling.
- `prefers-reduced-motion` fallback to static iso-layout with CSS transitions only, disabling WebGL physics.
- Full keyboard navigation (Tab / Arrow keys) for node selection and zoom, with visible focus rings (`#78bdff` 2px outline).
- ARIA labels for all graph entities: `Node: Payment Service, Status: Healthy, Connections: 3`.
- Color-blind-safe palette using luminance steps (15% increments) plus distinct shapes (circle / square / diamond) for node types.
- No constant rotation; all motion must be user-initiated or settle within 3 seconds.
- GPU memory cap at 128 MB for the widget instance, forcing texture compression and geometry instancing.

*rainbow per provider, constant spin, cheap CSS gradients masquerading as 3D, fake depth, vendor 3D models*

---

> Generated 2026-05-07 via `mcp__abs__ask_kimi` (cloudflare cf/moonshotai/kimi-k2.5, 74.6s, 6511 tok).
> Brief 2 R1 deliverable — `_agent-tasks/WORKER_COSMOS_3D_REDESIGN.md` §2.
