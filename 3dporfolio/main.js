import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls";
import "./style.css";

//3 Objects:
// 1. Scene: is like a container
// 2. Camera: there is a loot of camera but the most common in the perspective camera
// 3. Render

const scene = new THREE.Scene();
//First parameter is like the vision angle, the second is the aspect ratio, the last is the view frustrum to control the vision
const camera = new THREE.PerspectiveCamera(
  75,
  window.innerWidth / 2 / (window.innerHeight / 2),
  0.1,
  1000
);

const renderer = new THREE.WebGLRenderer({
  canvas: document.querySelector("#bg"),
});

renderer.setPixelRatio(window.devicePixelRatio);
renderer.setSize(window.innerWidth, window.innerHeight);
camera.position.setZ(30);

/**
 * Adding a Object: threejs already jave various types of geometry objects,
 * also materials (or we can build or own material with webgl)
 * 1. Geometry: the {x,y,z} position that makeup a shape
 * 2. Material: the wrapping material of the object
 * 3. Mesh: geometry + material
 */

const geometry = new THREE.TorusGeometry(10, 3, 16, 100);
const material = new THREE.MeshStandardMaterial({ color: 0xff6347 });
const torus = new THREE.Mesh(geometry, material);

scene.add(torus);

//To add light to the Material:
const pointLight = new THREE.PointLight(0xffffff);
pointLight.position.set(5, 5, 5);
const ambientLight = new THREE.AmbientLight(0xffffff);
// And we have to add it to the scene
scene.add(pointLight, ambientLight);

const lightHelper = new THREE.PointLightHelper(pointLight);
const gridHelper = new THREE.GridHelper(200, 50);
scene.add(lightHelper, gridHelper);

const controls = new OrbitControls(camera, renderer.domElement);

function addStar() {
  const geometry = new THREE.SphereGeometry(0.25, 24, 24);
  const material = new THREE.MeshStandardMaterial({ color: 0xffffff });
  const star = new THREE.Mesh(geometry, material);
  const [x, y, z] = Array(3)
    .fill()
    .map(() => THREE.MathUtils.randFloatSpread(100));
  star.position.set(x, y, z);
  scene.add(star);
}

Array(200)
  .fill()
  .forEach(() => addStar());

//Texture loader
const speceTexture = new THREE.TextureLoader().load("space.png");
scene.background = speceTexture;
//Texture mapping from 2D images to 3D Images

const fariTexture = new THREE.TextureLoader().load("foto_perfil.jpg");
const fari = new THREE.Mesh(
  new THREE.BoxGeometry(3, 3, 3),
  new THREE.MeshBasicMaterial({ map: fariTexture })
);

const moonTexture = new THREE.TextureLoader().load("moon.jpg");
const moon = new THREE.Mesh(
  new THREE.SphereGeometry(3, 32, 32),
  new THREE.MeshStandardMaterial({ map: moonTexture })
);
scene.add(moon);
fari.position.set(
  moon.position.x + 3,
  moon.position.y + 3,
  moon.position.z + 3
);
scene.add(fari);

function animate() {
  requestAnimationFrame(animate);
  torus.rotation.x += 0.01;
  torus.rotation.y += 0.005;
  torus.rotation.z += 0.01;
  moon.rotation.y += 0.005;
  fari.rotation.y += 0.005;

  controls.update();

  renderer.render(scene, camera); //for draw
}

animate();
