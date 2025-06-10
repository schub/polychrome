import { Hook, makeHook } from "phoenix_typed_hook";

type RGB = [number, number, number];
type Frame = { kind: "rgb"; data: number[] };

import * as THREE from "three";

import { VRButton } from "three/addons/webxr/VRButton.js";
import { PointerLockControls } from "three/addons/controls/PointerLockControls.js";
import Stats from "three/addons/libs/stats.module.js";
import { GUI } from "three/addons/libs/lil-gui.module.min.js";

const vertexShader = `
  varying vec2 vUv;
  varying vec3 vWorldPosition;

  void main() {
    vUv = uv;
    vWorldPosition = position;
    gl_Position = projectionMatrix * viewMatrix * modelMatrix * vec4(position, 1.0);
  }
`;

const fragmentShader = `
  uniform sampler2D uLEDTexture;
  uniform float uMask;
  uniform float uMaskSmoothness;
  uniform float uMaskSize;
  varying vec2 vUv;

  void main() {
    vec2 texCoord = floor(vec2(vUv.x, 1.0 - vUv.y) * 8.0) / 8.0 + vec2(0.5 / 8.0);
    vec3 color = texture2D(uLEDTexture, texCoord).rgb;

    vec2 cellUv = fract(vec2(vUv.x, 1.0 - vUv.y) * 8.0);
    vec2 center = vec2(0.5, 0.5);
    float distance = length(cellUv - center);

    float circle = smoothstep(uMaskSize, uMaskSize - uMaskSmoothness, distance);
    float mask = mix(1.0, circle, uMask);

    gl_FragColor = vec4(color * mask, 1.0);
  }
`;

const skyVertexShader = `
  varying vec2 vUv;
  varying vec3 vWorldPosition;

  void main() {
    vUv = uv;
    vWorldPosition = position;
    gl_Position = projectionMatrix * viewMatrix * modelMatrix * vec4(position, 1.0);
  }
`;

const skyFragmentShader = `
  varying vec2 vUv;
  varying vec3 vWorldPosition;

  // Simple hash function
  float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
  }

  // Star field - uses UV coordinates for truly fixed positioning
  float stars(vec2 uv) {
    float gridSize = 100.0;
    vec2 grid = floor(uv * gridSize);
    vec2 cellUV = fract(uv * gridSize);

    float jx = hash(grid + 0.1);
    float jy = hash(grid + 0.2);
    vec2 starPos = vec2(jx, jy);

    float starSeed = hash(grid);
    float isStar = step(0.70, starSeed);

    float dist = length(cellUV - starPos);
    float star = smoothstep(0.03, 0.0, dist) * isStar;

    return star * 1.5;
  }

  // Simple nebula - uses UV coordinates
  vec3 nebula(vec2 uv) {
    // Create a few large, stable nebula regions
    vec2 nebula1 = uv - vec2(0.3, 0.7);
    vec2 nebula2 = uv - vec2(0.8, 0.2);

    float dist1 = length(nebula1);
    float dist2 = length(nebula2);

    float nebula1_intensity = smoothstep(0.3, 0.0, dist1) * 0.1;
    float nebula2_intensity = smoothstep(0.2, 0.0, dist2) * 0.1;

    vec3 color1 = vec3(0.1, 0.2, 0.8); // Blue
    vec3 color2 = vec3(0.8, 0.1, 0.3); // Pink

    return color1 * nebula1_intensity + color2 * nebula2_intensity;
  }

  void main() {
    // Base night sky color
    vec3 skyColor = vec3(0.02, 0.03, 0.08);

    // Add stars
    float starField = stars(vUv);
    skyColor += vec3(starField);

    // Add nebula
    skyColor += nebula(vUv);

    // Add subtle gradient from horizon to zenith
    float gradient = pow(vUv.y, 0.3);
    skyColor = mix(skyColor, skyColor * 1.2, gradient);

    gl_FragColor = vec4(skyColor, 1.0);
  }
`;

const PANEL_SIZE = 1.6;
const PANEL_DISTANCE_FROM_GROUND = 0.4;
const PANEL_DEPTH = 0.2;

class Pixels3dHook extends Hook {
  mounted() {
    const canvas = this.el as HTMLCanvasElement;
    const id = canvas.id;
    const numPanels = parseInt(this.el.getAttribute("num-panels") || "10");

    const textures: THREE.DataTexture[] = [];
    const frontMaterials: THREE.ShaderMaterial[] = [];
    const backMaterials: THREE.ShaderMaterial[] = [];
    const panels: THREE.Object3D[] = [];
    const pixels: RGB[] = Array(numPanels * 8 * 8).fill([0, 0, 0]);
    let diameter = 20.0;

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.xr.enabled = true;
    renderer.setPixelRatio(window.devicePixelRatio);
    renderer.setSize(window.innerWidth, window.innerHeight);
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.el.appendChild(renderer.domElement);
    document.body.appendChild(VRButton.createButton(renderer));

    const scene = new THREE.Scene();

    const skyGeometry = new THREE.SphereGeometry(1000, 32, 32);
    const skyMaterial = new THREE.ShaderMaterial({
      vertexShader: skyVertexShader,
      fragmentShader: skyFragmentShader,
      side: THREE.BackSide,
    });
    const skySphere = new THREE.Mesh(skyGeometry, skyMaterial);
    skySphere.castShadow = false;
    skySphere.receiveShadow = false;
    skyMaterial.depthWrite = false;
    scene.add(skySphere);

    const camera = new THREE.PerspectiveCamera(
      75,
      window.innerWidth / window.innerHeight,
      0.1,
      10000
    );

    const moveInput = new THREE.Vector2();
    let vrMovementObject: THREE.Object3D;

    const controls = new PointerLockControls(camera, renderer.domElement);
    controls.object.position.set(0, 1.8, 0);
    scene.add(controls.object);

    vrMovementObject = new THREE.Object3D();
    scene.add(vrMovementObject);

    canvas.addEventListener("click", () => {
      if (!controls.isLocked) {
        controls.lock();
      }
    });

    document.addEventListener("keydown", (event) => {
      switch (event.code) {
        case "ArrowUp":
        case "KeyW":
          moveInput.y = 1;
          break;

        case "ArrowLeft":
        case "KeyA":
          moveInput.x = -1;
          break;

        case "ArrowDown":
        case "KeyS":
          moveInput.y = -1;
          break;

        case "ArrowRight":
        case "KeyD":
          moveInput.x = 1;
          break;
      }
    });

    document.addEventListener("keyup", (event) => {
      switch (event.code) {
        case "ArrowUp":
        case "KeyW":
          moveInput.y = 0;
          break;

        case "ArrowLeft":
        case "KeyA":
          moveInput.x = 0;
          break;

        case "ArrowDown":
        case "KeyS":
          moveInput.y = 0;
          break;

        case "ArrowRight":
        case "KeyD":
          moveInput.x = 0;
          break;
      }
    });

    const updateMeshes = () => {
      for (let i = 0; i < numPanels; i++) {
        const mesh = panels[i];
        const radius = diameter / 2;
        const angle = (i / numPanels) * Math.PI * 2;
        mesh.position.set(
          radius * Math.sin(angle),
          PANEL_SIZE / 2 + PANEL_DISTANCE_FROM_GROUND,
          radius * Math.cos(angle)
        );
        mesh.rotation.y = angle + Math.PI;
      }
    };

    for (let i = 0; i < numPanels; i++) {
      const data = new Uint8Array(8 * 8 * 4);
      for (let j = 0; j < data.length; j += 4) {
        data[j] = Math.floor(0);
        data[j + 1] = Math.floor(0);
        data[j + 2] = Math.floor(0);
        data[j + 3] = 255;
      }

      const texture = new THREE.DataTexture(data, 8, 8, THREE.RGBAFormat);
      texture.needsUpdate = true;
      textures.push(texture);

      const frontUniforms = {
        uLEDTexture: { value: texture },
        uMask: { value: 0.2 },
        uMaskSmoothness: { value: 1.0 },
        uMaskSize: { value: 1.0 },
      };

      const backUniforms = {
        uLEDTexture: { value: texture },
        uMask: { value: 1.0 },
        uMaskSmoothness: { value: 0.05 },
        uMaskSize: { value: 0.1 },
      };

      const frontMaterial = new THREE.ShaderMaterial({
        uniforms: frontUniforms,
        vertexShader,
        fragmentShader,
      });
      frontMaterials.push(frontMaterial);

      const backMaterial = new THREE.ShaderMaterial({
        uniforms: backUniforms,
        vertexShader,
        fragmentShader,
      });
      backMaterials.push(backMaterial);

      const frontMesh = new THREE.Mesh(
        new THREE.PlaneGeometry(PANEL_SIZE, PANEL_SIZE),
        frontMaterial
      );

      const backMesh = new THREE.Mesh(
        new THREE.PlaneGeometry(PANEL_SIZE, PANEL_SIZE),
        backMaterial
      );

      backMesh.rotateY(Math.PI);
      backMesh.translateZ(PANEL_DEPTH);

      const centerMeshGeo = new THREE.BoxGeometry(
        PANEL_SIZE,
        PANEL_SIZE,
        PANEL_DEPTH
      );
      const centerMeshMat = new THREE.MeshStandardMaterial({
        color: 0xffffff,
        roughness: 0.4,
      });
      const centerMesh = new THREE.Mesh(centerMeshGeo, centerMeshMat);
      centerMesh.translateZ(-PANEL_DEPTH / 2);
      centerMesh.scale.set(1.0, 1.0, 0.95);

      const obj = new THREE.Object3D();
      obj.add(frontMesh);
      obj.add(backMesh);
      obj.add(centerMesh);

      panels.push(obj);
      vrMovementObject.add(obj);
    }

    updateMeshes();

    const light = new THREE.HemisphereLight(0xb0c4de, 0x556b2f, 0.5);
    light.position.set(0.5, 1, 0.75);
    vrMovementObject.add(light);

    const textureLoader = new THREE.TextureLoader();
    const groundAlbedoTexture = textureLoader.load(
      "/images/patchy-meadow1/patchy-meadow1_albedo.png"
    );
    const groundRoughnessTexture = textureLoader.load(
      "/images/patchy-meadow1/patchy-meadow1_roughness.png"
    );
    const groundNormalTexture = textureLoader.load(
      "/images/patchy-meadow1/patchy-meadow1_normal-ogl.png"
    );

    groundAlbedoTexture.wrapS = groundAlbedoTexture.wrapT =
      THREE.RepeatWrapping;
    groundRoughnessTexture.wrapS = groundRoughnessTexture.wrapT =
      THREE.RepeatWrapping;
    groundNormalTexture.wrapS = groundNormalTexture.wrapT =
      THREE.RepeatWrapping;

    const textureRepeat = 1000;
    groundAlbedoTexture.repeat.set(textureRepeat, textureRepeat);
    groundRoughnessTexture.repeat.set(textureRepeat, textureRepeat);
    groundNormalTexture.repeat.set(textureRepeat, textureRepeat);

    const groundGeometry = new THREE.BoxGeometry(2000, 0.1, 2000);
    const groundMaterial = new THREE.MeshStandardMaterial({
      map: groundAlbedoTexture,
      roughnessMap: groundRoughnessTexture,
      normalMap: groundNormalTexture,
      normalScale: new THREE.Vector2(1, 1),
      metalness: 0.0,
    });
    const groundMesh = new THREE.Mesh(groundGeometry, groundMaterial);
    vrMovementObject.add(groundMesh);

    window.addEventListener("resize", onWindowResize);

    const stats = new Stats();
    document.body.appendChild(stats.dom);

    const params = {
      exposure: 1.0,
    };
    renderer.toneMappingExposure = Math.pow(params.exposure, 4.0);

    const gui = new GUI();

    gui
      .addFolder("Tonemapping")
      .add(params, "exposure", 0.1, 2)
      .onChange(function (value) {
        renderer.toneMappingExposure = Math.pow(value, 4.0);
      });

    function onWindowResize() {
      camera.aspect = window.innerWidth / window.innerHeight;
      camera.updateProjectionMatrix();
      renderer.setSize(window.innerWidth, window.innerHeight);
    }

    var lastTime = performance.now();

    function animate(time: DOMHighResTimeStamp) {
      const delta = (time - lastTime) * 0.001;
      lastTime = time;

      if (!renderer.xr.isPresenting) {
        controls.moveForward(moveInput.normalize().y * delta * 4.0);
        controls.moveRight(moveInput.normalize().x * delta * 4.0);
      } else {
        const moveSpeed = delta * 4.0;
        const normalizedInput = moveInput.normalize();

        if (normalizedInput.length() > 0) {
          const xrCamera = renderer.xr.getCamera();

          const forward = new THREE.Vector3(0, 0, -1);
          forward.applyQuaternion(xrCamera.quaternion);
          forward.y = 0;
          forward.normalize();

          const right = new THREE.Vector3(1, 0, 0);
          right.applyQuaternion(xrCamera.quaternion);
          right.y = 0;
          right.normalize();

          const movement = new THREE.Vector3();
          movement.addScaledVector(forward, normalizedInput.y * moveSpeed);
          movement.addScaledVector(right, normalizedInput.x * moveSpeed);

          vrMovementObject.position.sub(movement);
        }
      }

      stats.update();

      for (let i = 0; i < numPanels; i++) {
        for (let j = 0; j < 64; j++) {
          let textureIdx = numPanels - i - 1;
          const pixelIdx = i * 64 + j;
          if (pixels[pixelIdx]) {
            textures[textureIdx].image.data[j * 4] = pixels[pixelIdx][0];
            textures[textureIdx].image.data[j * 4 + 1] = pixels[pixelIdx][1];
            textures[textureIdx].image.data[j * 4 + 2] = pixels[pixelIdx][2];
            textures[textureIdx].image.data[j * 4 + 3] = 255;
            textures[textureIdx].needsUpdate = true;
          }
        }
      }

      renderer.render(scene, camera);
    }

    renderer.setAnimationLoop(animate);

    type Param = { param: { diameter?: number; move?: [number, number] } };

    this.handleEvent(`param:${id}`, ({ param: param }: Param) => {
      if (param.diameter) {
        diameter = param.diameter;
        updateMeshes();
      }
      if (param.move) {
        moveInput.set(param.move[0], param.move[1]);
      }
    });

    [`frame:${id}`, "frame:pixels-*"].forEach((event) => {
      this.handleEvent(event, ({ frame: frame }: { frame: Frame }) => {
        switch (frame.kind) {
          case "rgb": {
            pixels.push(...Array(numPanels * 64).fill([0, 0, 0]));
            const numPixels = frame.data.length / 3;
            pixels.splice(0, pixels.length);
            for (let i = 0; i < numPixels; i++) {
              const pixelOffset = i * 3;
              const r = frame.data[pixelOffset];
              const g = frame.data[pixelOffset + 1];
              const b = frame.data[pixelOffset + 2];

              pixels[i] = [r, g, b];
            }
            break;
          }
          default: {
            throw new Error("Unsupported frame kind: " + frame.kind);
          }
        }
      });
    });
  }
}

export default makeHook(Pixels3dHook);
