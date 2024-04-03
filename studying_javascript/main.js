var car = {
  name: "Alta Maquina",
  drive: () => {
    return "pepe trueno";
  },
};

console.log(car.drive());
console.log(car["name"]);

//Deleting a propertie of the object
delete car.name;

//Modifying array
var array = ["string", { name: "pepe" }, 100];
array.shift();
array.pop();
array.unshift("something inserted at the beginin"); //Inserts new elements at the start of an array
array.push("something at the end");
var start = 1;
var numberOfElement = 2;
array.splice(start, numberOfElement);
// Can do but is bad
array.somePropertie = "Something";
// ┌───────────────┬────────┬─────────────┐
// │    (index)    │  name  │   Values    │
// ├───────────────┼────────┼─────────────┤
// │       0       │        │  'string'   │
// │       1       │ 'pepe' │             │
// │       2       │        │     100     │
// │ somePropertie │        │ 'Something' │
// └───────────────┴────────┴─────────────┘
console.log(array);

//Functions are callable objects (you have to use the () syntax to execute them), and have scope like regular objects
// the closure is what is between {} closes and encapsulates and it keeps together all symbols
function randomeName() {
  var a = 10;

  function add() {
    return a + 90;
  }
  console.log(add());
}
//Global scope (are in the window object): if can't find some variable in the current scope, automatically inferring suggesting
// that we want to keep going up scope until find the variable

//If you dont use a decorator of variable infers global scope
function someFun() {
  iferGlobal = "Something";
}
someFun();
