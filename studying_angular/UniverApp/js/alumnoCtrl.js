app.controller("alumnoCtrl", [
  "$scope",
  "$routeParams",
  "$http",
  function ($scope, $routeParams, $http) {
    $scope.setActive("mAlumnos");
    $scope.alumno = {};
    $scope.actualizado = false;
    var codigo = Number($routeParams.codigo);

    $http
      .get("json/mock-data.json")
      .then(function (data) {
        return data.data.alumnos;
      })
      .then(function (data) {
        $scope.alumno = data.find((alumno) => alumno.codigo === codigo);
        if (!$scope.alumno) {
          window.location = "#!/alumnos";
        }
      });

    $scope.guardarAlumno = function () {
      let jsonData = JSON.parse(fs.readFileSync("json/mock-data.json"));
      console.log(jsonData);
    };
  },
]);
