import { Hook, makeHook } from "phoenix_typed_hook";

type RGB = [number, number, number];
type Frame = { kind: "rgb"; data: number[] };

import * as THREE from "three";

import { VRButton } from "three/addons/webxr/VRButton.js";
import { PointerLockControls } from "three/addons/controls/PointerLockControls.js";
import { RGBELoader } from "three/addons/loaders/RGBELoader.js";
import Stats from "three/addons/libs/stats.module.js";
import { GUI } from "three/addons/libs/lil-gui.module.min.js";

const vertexShader = `
  varying vec2 vUv;

  void main() {
    vUv = uv;
    gl_Position = projectionMatrix * viewMatrix * modelMatrix * vec4(position, 1.0);
  }
`;

const fragmentShader = `
  uniform sampler2D uLEDTexture;
  uniform float strength;
  varying vec2 vUv;

  void main() {
    vec2 texCoord = floor(vec2(vUv.x, 1.0 - vUv.y) * 8.0) / 8.0 + vec2(0.5 / 8.0); // snap to LED cell
    vec3 color = texture2D(uLEDTexture, texCoord).rgb;
    gl_FragColor = vec4(color * strength, 1.0);
  }
`;

const PANEL_SIZE = 1.6;
const PANEL_DISTANCE_FROM_GROUND = 0.4;
const NUM_PANELS = 10;

class Pixels3dHook extends Hook {
  mounted() {
    const canvas = this.el as HTMLCanvasElement;
    const id = canvas.id;

    const textures: THREE.DataTexture[] = [];
    const materials: THREE.ShaderMaterial[] = [];
    const meshes: THREE.Mesh[] = [];
    const pixels: RGB[] = [];
    let diameter = 20.0;

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.xr.enabled = true;
    renderer.setPixelRatio(window.devicePixelRatio);
    renderer.setSize(window.innerWidth, window.innerHeight);
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.el.appendChild(renderer.domElement);
    document.body.appendChild(VRButton.createButton(renderer));

    const scene = new THREE.Scene();

    new RGBELoader()
      .setPath("/images/hdr/")
      .load("moonless_golf_1k.hdr", (texture) => {
        texture.mapping = THREE.EquirectangularReflectionMapping;
        scene.background = texture;
        scene.environment = texture;
      });

    const camera = new THREE.PerspectiveCamera(
      75,
      window.innerWidth / window.innerHeight,
      0.1,
      1000
    );

    const moveInput = new THREE.Vector2();

    const controls = new PointerLockControls(camera, renderer.domElement);
    controls.object.position.set(0, 1.8, 0);
    scene.add(controls.object);

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
      for (let i = 0; i < NUM_PANELS; i++) {
        const mesh = meshes[i];
        const radius = diameter / 2;
        const angle = (i / NUM_PANELS) * Math.PI * 2;
        mesh.position.set(
          radius * Math.sin(angle),
          PANEL_SIZE / 2 + PANEL_DISTANCE_FROM_GROUND,
          radius * Math.cos(angle)
        );
        mesh.rotation.y = angle + Math.PI;
      }
    };

    for (let i = 0; i < NUM_PANELS; i++) {
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

      const uniforms = {
        uLEDTexture: { value: texture },
        strength: { value: 1.0 },
      };

      const material = new THREE.ShaderMaterial({
        uniforms,
        vertexShader,
        fragmentShader,
      });
      materials.push(material);

      const mesh = new THREE.Mesh(
        new THREE.PlaneGeometry(PANEL_SIZE, PANEL_SIZE),
        material
      );
      meshes.push(mesh);
      scene.add(mesh);
    }

    updateMeshes();

    const light = new THREE.HemisphereLight(0xeeeeff, 0x777788, 0.5);
    light.position.set(0.5, 1, 0.75);
    scene.add(light);

    const groundGeometry = new THREE.BoxGeometry(2000, 0.1, 2000);
    const groundMaterial = new THREE.MeshStandardMaterial();
    const groundMesh = new THREE.Mesh(groundGeometry, groundMaterial);
    scene.add(groundMesh);

    window.addEventListener("resize", onWindowResize);

    const stats = new Stats();
    document.body.appendChild(stats.dom);

    const params = {
      exposure: 0.5,
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

      if (controls.isLocked) {
        controls.object.position.setY(1.8);
        controls.moveForward(moveInput.y * delta * 4.0);
        controls.moveRight(moveInput.x * delta * 4.0);
      }

      stats.update();

      for (let i = 0; i < NUM_PANELS; i++) {
        for (let j = 0; j < 64; j++) {
          let textureIdx = NUM_PANELS - i - 1;
          const pixelIdx = i * 64 + j;
          textures[textureIdx].image.data[j * 4] = pixels[pixelIdx][0];
          textures[textureIdx].image.data[j * 4 + 1] = pixels[pixelIdx][1];
          textures[textureIdx].image.data[j * 4 + 2] = pixels[pixelIdx][2];
          textures[textureIdx].image.data[j * 4 + 3] = 255;
          textures[textureIdx].needsUpdate = true;
        }
      }

      renderer.render(scene, camera);
    }

    renderer.setAnimationLoop(animate);

    type Param = { param: { diameter?: number; strength?: number } };

    this.handleEvent(`param:${id}`, ({ param: param }: Param) => {
      if (param.diameter) {
        diameter = param.diameter;
        updateMeshes();
      }
      if (param.strength) {
        materials.forEach((material) => {
          material.uniforms.strength.value = param.strength;
        });
      }
    });

    [`frame:${id}`, "frame:pixels-*"].forEach((event) => {
      this.handleEvent(event, ({ frame: frame }: { frame: Frame }) => {
        switch (frame.kind) {
          case "rgb": {
            const numPixels = frame.data.length / 3;
            pixels.splice(0, pixels.length);
            pixels.push();
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
