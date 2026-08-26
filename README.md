# 🌌 Relativistic Raytracer - Unity Implementation

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/)
[![Unity](https://img.shields.io/badge/Unity-2023.2.20f1-blue.svg)](https://unity.com/)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-blue)](https://github.com/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![HLSL](https://img.shields.io/badge/HLSL-Shader%20Model%205.0-orange.svg)](https://docs.microsoft.com/en-us/windows/win32/direct3dhlsl/dx-graphics-hlsl)

(Visit Vulkan Implementation: https://github.com/tucoff/relativistic-raytracer-vulkan)

## 📋 Project Overview

This project implements a **real-time relativistic raytracer** using **Unity Engine and HLSL shaders**, developed as part of academic research and presented at SIBGRAPI 2026. The system simulates light propagation in curved spacetime, enabling visualization of relativistic phenomena such as gravitational lensing, frame-dragging, redshift, and black hole event horizons.

*Inspired by [Sebastian Lague's Ray Tracing project](https://github.com/SebLague/Ray-Tracing), this implementation extends the original concept to include relativistic physics and automated benchmarking systems.*

### 🎯 Key Features

- **Three Physical Metrics**: 
  - **Newton**: Classical Euclidean space-time
  - **Schwarzschild**: Static black hole (spherically symmetric)
  - **Kerr**: Rotating black hole with frame-dragging effects
- **Two Numerical Integrators**: 
  - **Euler**: First-order integration (faster, less accurate)
  - **Runge-Kutta 4**: Fourth-order integration (slower, more accurate)
- **Real-Time Rendering**: GPU implementation via Unity HLSL compute shaders
- **Automated Benchmark System**: Performance metrics (FPS) and visual quality collection
- **Multiple Test Scenes**: From simple black holes to complete planetary systems
- **High-Resolution Planetary Textures**: 2K textures for Earth, Mars, Jupiter, and other celestial bodies
- **Dynamic Skyboxes**: Multiple universe environments and procedural backgrounds
## 🏗️ Architecture

### Project Structure
```
Assets/
├── Scripts/                    # C# source code
│   ├── RayTracingManager.cs   # Main engine controller (396 lines)
│   ├── BenchmarkManager.cs    # Automated benchmark system
│   ├── Benchmark/             # Benchmark configuration and CSV export
│   ├── Data Types/            # Physics data structures
│   ├── Helpers/               # Utility classes
│   ├── Render Types/          # Ray-traced objects (spheres, meshes)
│   └── Shaders/               # HLSL shaders
│       └── RayTracing.shader  # Main relativistic raytracing shader (585 lines)
├── Textures/                  # Visual assets
│   ├── 2k_*.jpg              # 2K planetary textures
│   └── *.cubemap             # Skybox environments
├── Scenes/                    # Unity scenes
├── Prefabs/                   # Reusable game objects
└── Graphics/                  # Additional visual assets
```

### Rendering Pipeline

1. **Unity Initialization**: Camera setup and shader parameter binding
2. **Scene Configuration**: Load celestial bodies, masses, and orbital parameters
3. **Geodesic Integration**: Numerical integration of spacetime geodesics
4. **Ray Marching**: Step-by-step light path calculation in curved spacetime
5. **Intersection Testing**: Collision detection with planetary surfaces and event horizons
6. **Texture Mapping**: Apply high-resolution planetary textures using spherical coordinates
7. **Skybox Rendering**: Environmental lighting and cosmic background
8. **Benchmark Collection**: Automated FPS measurement and screenshot capture

### Metric Implementation

#### 🍎 Newton (Euclidean Metric)
Classical Newtonian gravity in flat spacetime:
```hlsl
// Simple gravitational acceleration
float3 toSphere = normalize(_SpherePos - ray.origin);
float d2 = dot(ray.origin - _SpherePos, ray.origin - _SpherePos);
float d2_3 = d2 * sqrt(d2);
accel += toSphere * (sphereRadiusAdjusted * 0.5) / d2_3;
```

#### ⚫ Schwarzschild (Static Black Hole)
Relativistic geodesic equations for spherically symmetric spacetime:
```hlsl
// Gravitational deflection with angular momentum conservation
float3 h = cross(-toSphere, v);
float d2_5 = d2_2 * d2_3;
accel += toSphere * (1.5 * sphereRadiusAdjusted * dot(h, h)) / d2_5;
```

#### 🌀 Kerr (Rotating Black Hole)
Frame-dragging effects in rotating black hole spacetime:
```hlsl
// Schwarzschild deflection + frame-dragging correction
float3 a_schwarzschild = -r_vec * (1.5 * sphereRadiusAdjusted * dot(h, h)) / d2_5;
float3 spin_vec = KERR_SPIN_AXIS * sphereRadiusAdjusted * _SpinSpeed;
float3 H = (2.0 / d2_5) * (3.0 * r_vec * dot(spin_vec, r_vec) - spin_vec * d2_2);
float3 a_frame_drag = -cross(v, H);
accel += a_schwarzschild + a_frame_drag;
```

### Integration System

#### ⚡ Euler (1st Order)
Fast but less accurate integration:
```hlsl
void StepEuler(inout float3 position, inout float3 velocity, float stepSize) {
    float3 accel = GetGravitationalAcceleration(position, velocity);
    velocity = normalize(velocity + accel * stepSize);
    position += velocity * stepSize;
}
```

## 📊 Key Results

### Performance Benchmark

The automated benchmark system collects detailed metrics across multiple configurations:

- **Resolutions**: 144p (256×144), 480p (853×480), 720p (1280×720), 1080p (1920×1080)
- **Metrics**: Newton, Schwarzschild, Kerr  
- **Integrators**: Euler vs RK4
- **Scenes**: 6 different test scenarios (black holes, planetary systems, multi-body configurations)
- **Camera Angles**: Multiple viewpoints per scene (Front, Peripheral, Above, Diagonal, Tangent)
- **Step Sizes**: Small (1.0), Medium (52.0), Large (260.0)
- **Gravitational Masses**: From 10 solar masses to extreme regimes

#### 📈 Performance Cross-over (Estimated)

| Resolution | Newton (Euler) | Schwarzschild (RK4) | Kerr (RK4) |
|-----------|---------------|-------------------|------------|
| 144p      | ~800-1200 FPS | ~200-400 FPS     | ~150-300 FPS |
| 480p      | ~200-400 FPS  | ~60-120 FPS      | ~45-90 FPS |
| 720p      | ~120-200 FPS  | ~35-70 FPS       | ~25-55 FPS |
| 1080p     | ~60-120 FPS   | ~20-40 FPS       | ~15-30 FPS |

*Performance varies significantly based on scene complexity, step size, and gravitational field strength.*

#### 🎯 Gravitational Mass Limits

- **Schwarzschild Radius**: RS = 2GM/c² ≈ 29.5 km (for 10 solar masses)
- **Event Horizon Detection**: Automatic rendering of black silhouettes
- **Ergosphere Region**: Frame-dragging simulation in Kerr metric
- **Gravitational Lensing**: Light deflection and multiple image formation
- **Redshift Effects**: Doppler shifting in strong gravitational fields

### Visual Quality Features

- **High-Resolution Textures**: 2K planetary surface maps (Earth, Mars, Jupiter, Mercury, Venus, Saturn, Uranus, Neptune)
- **Dynamic Skyboxes**: Multiple cosmic environments and procedural backgrounds
- **Relativistic Aberration**: Light ray bending visualization
- **Accretion Disk Simulation**: Hot gas dynamics around rotating black holes
- **Ring System Rendering**: Saturn-like planetary rings with gravitational effects

## 🚀 How to Run

### Prerequisites

- **Unity 2023.2.20f1** or newer
- **Windows 10/11**, **macOS 10.15+**, or **Ubuntu 18.04+**
- **DirectX 11** or **OpenGL 4.1** support
- **4+ GB VRAM** recommended for high-resolution rendering
- **8+ GB RAM** for texture loading and benchmark operations

### Installation

#### Unity Hub Method (Recommended)
```bash
# 1. Install Unity Hub from https://unity.com/download

# 2. Install Unity 2023.2.20f1 through Unity Hub

# 3. Clone the repository
git clone https://github.com/your-username/Ray-Tracing-Old.git
cd Ray-Tracing-Old

# 4. Open the project in Unity Hub
# File -> Open -> Select the Ray-Tracing-Old folder

# 5. Wait for Unity to import all assets (may take several minutes)

# 6. Open the main scene: Assets/Scenes/MainScene.unity

# 7. Press Play to start the application
```

### Controls

| Key | Function |
|-----|----------|
| `W/A/S/D` | Camera movement (when First Person enabled) |
| `Mouse` | Camera rotation (when First Person enabled) |
| `H` | Toggle relativistic mode (Newton ↔ Relativistic) |
| `P` | Toggle point mode (single pixel rendering) |
| `L` | Display FPS information in console |
| `1-6` | Switch between test scenes |
| `Escape` | Toggle cursor lock (in First Person mode) |
| `Space` | Reset camera position |

### Scene Descriptions

1. **Scene 1**: Simple Schwarzschild black hole with minimal background
2. **Scene 2**: Black hole with accretion disk and ring system
## 📚 Academic References & Theoretical Foundation

This project is grounded in the scientific literature of general relativity and computational physics:

### Core Physics References
1. **Schwarzschild, K.** (1916). "Über das Gravitationsfeld eines Massenpunktes nach der Einsteinschen Theorie"
2. **Kerr, R.P.** (1963). "Gravitational field of a spinning mass as an example of algebraically special metrics"
3. **Chandrasekhar, S.** (1983). "The Mathematical Theory of Black Holes"
4. **Marck, J.A.** (1996). "Short-cut method of solution of geodesic equations for Schwarzschild black hole"

### Computational & Visualization References
5. **James, O., von Tunzelmann, E., Franklin, P., Thorne, K.S.** (2015). "Gravitational lensing by spinning black holes in astrophysics, and in the movie Interstellar"
6. **Müller, T.** (2014). "GeoViS—Relativistic ray tracing in four-dimensional spacetimes"
7. **Riazuelo, A.** (2019). "Seeing relativity: Ray tracing in a relativistic world"

### Numerical Methods References
8. **Press, W.H., Teukolsky, S.A., Vetterling, W.T., Flannery, B.P.** (2007). "Numerical Recipes: The Art of Scientific Computing"
9. **Butcher, J.C.** (2016). "Numerical Methods for Ordinary Differential Equations"

## 🤝 Contributions

Contributions are welcome! This project is particularly suited for:

- **Physics Students**: Implementing additional metrics (Reissner-Nordström, Kerr-Newman)
- **Computer Graphics Researchers**: Optimizing ray marching algorithms
- **Unity Developers**: Enhancing visual effects and UI systems
- **Computational Physicists**: Improving numerical integration methods

### Contributing Guidelines

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/reissner-nordstrom-metric`)
3. Implement your changes with appropriate documentation
4. Add test cases and benchmark configurations
5. Commit your changes (`git commit -am 'Add Reissner-Nordström charged black hole metric'`)
6. Push to the branch (`git push origin feature/reissner-nordstrom-metric`)
7. Open a Pull Request with detailed description

## 📜 License & Attribution

This project is licensed under the **MIT License with Academic Attribution Requirements** - see the [LICENSE](LICENSE) file for complete terms and the [Academic License Guide](ACADEMIC_LICENSE_GUIDE.md) for usage examples.

### Unity Asset Credits
- **Planetary Textures**: NASA/JPL public domain imagery
- **Skybox Environments**: Various Creative Commons sources
- **Unity Packages**: Input System, Recorder, Test Framework (Unity Technologies)

## 👨‍💻 Authors & Acknowledgments

**Project Extension**: Developed as part of academic research at [Your Institution]

**Original Ray Tracing Foundation**: [Sebastian Lague](https://github.com/SebLague) - Unity ray tracing architecture

**Academic Supervision**: [Supervisor Names and Affiliations]

### Special Thanks
- **NASA/JPL**: For high-quality planetary texture data
- **Unity Technologies**: For the robust game engine and shader system
- **General Relativity Community**: For theoretical foundations and numerical methods
- **Sebastian Lague**: For the inspiring original project and educational content

---

*"The universe is not only stranger than we imagine, it is stranger than we can imagine. But with mathematics and computation, we can at least render its beauty."* - Adapted from J.B.S. Haldane

### 🔗 Related Resources

- **Original Project**: [Sebastian Lague's Ray Tracing](https://github.com/SebLague/Ray-Tracing)
- **Educational Video**: [Ray Tracing Explained](https://youtu.be/Qz0KTGYJtUk)
- **Unity Documentation**: [HLSL Shaders](https://docs.unity3d.com/Manual/SL-ShaderPrograms.html)
- **General Relativity**: [Spacetime and Geometry by Sean Carroll](https://www.preposterousuniverse.com/grnotes/)
- **Numerical Methods**: [Numerical Recipes Online](http://numerical.recipes/)

## 👨‍💻 Authors & Acknowledgments

**Project Extension**: Developed as part of academic research at [Your Institution]

**Original Ray Tracing Foundation**: [Sebastian Lague](https://github.com/SebLague) - Unity ray tracing architecture

**Academic Supervision**: [Supervisor Names and Affiliations]

### Special Thanks
- **NASA/JPL**: For high-quality planetary texture data
- **Unity Technologies**: For the robust game engine and shader system
- **General Relativity Community**: For theoretical foundations and numerical methods
- **Sebastian Lague**: For the inspiring original project and educational content

---

*"The universe is not only stranger than we imagine, it is stranger than we can imagine. But with mathematics and computation, we can at least render its beauty."* - Adapted from J.B.S. Haldane

### 🔗 Related Resources

- **Original Project**: [Sebastian Lague's Ray Tracing](https://github.com/SebLague/Ray-Tracing)
- **Educational Video**: [Ray Tracing Explained](https://youtu.be/Qz0KTGYJtUk)
- **Unity Documentation**: [HLSL Shaders](https://docs.unity3d.com/Manual/SL-ShaderPrograms.html)
- **General Relativity**: [Spacetime and Geometry by Sean Carroll](https://www.preposterousuniverse.com/grnotes/)
- **Numerical Methods**: [Numerical Recipes Online](http://numerical.recipes/)
3. **Scene 3**: Multiple gravitational bodies interaction
4. **Scene 4**: Planetary system with textured celestial bodies
5. **Scene 5**: Complex multi-body orbital mechanics
6. **Scene 6**: Full solar system with dynamic lighting and skybox

### Benchmark Mode

To run automated benchmarks, ensure the `BenchmarkAutomator` component is active:

```csharp
// In Unity Inspector, find BenchmarkAutomator GameObject
// Ensure all required references are set:
// - RayTracingManager reference
// - BenchmarkConfiguration reference

// The system will automatically:
// 1. Capture baseline (non-relativistic) screenshots
// 2. Run full benchmark across all configurations
// 3. Export results to CSV files in Benchmarks/ folder
// 4. Generate performance comparison data
```

**Benchmark Output**:
- **Screenshots**: `Benchmarks/*.png` (performance-labeled images)
- **CSV Data**: `Benchmarks/benchmark_results.csv` (detailed metrics)
- **Performance Reports**: FPS data across all configurations
#### 🎯 Runge-Kutta 4 (4th Order)
More accurate but computationally expensive:
```hlsl
void StepRK4(inout float3 position, inout float3 velocity, float stepSize) {
    // Four-stage Runge-Kutta integration
    float3 k1_v = GetGravitationalAcceleration(position, velocity);
    float3 k2_v = GetGravitationalAcceleration(position + 0.5*stepSize*velocity, 
                                               velocity + 0.5*stepSize*k1_v);
    float3 k3_v = GetGravitationalAcceleration(position + 0.5*stepSize*(velocity + 0.5*stepSize*k1_v),
                                               velocity + 0.5*stepSize*k2_v);
    float3 k4_v = GetGravitationalAcceleration(position + stepSize*(velocity + stepSize*k2_v),
                                               velocity + stepSize*k3_v);
    
    velocity += (stepSize/6.0) * (k1_v + 2*k2_v + 2*k3_v + k4_v);
    velocity = normalize(velocity);
    position += stepSize * velocity;
}
```
