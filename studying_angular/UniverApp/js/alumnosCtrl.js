app.controller('alumnosCtrl', ['$scope', '$http', function ($scope, $http) {
    $scope.setActive("mAlumnos");

    $scope.alumnos = {};
    $scope.posicion = 5;

    $http.get('json/mock-data.json').then(function(data){
        $scope.alumnos = data.data.alumnos;
    });

    $scope.siguientes = function () {
        if( $scope.alumnos.length > $scope.posicion) {
            $scope.posicion +=5;
        }
    }
    
    $scope.anteriores = function() {
        if($scope.posicion > 5) {
            $scope.posicion -=5;
        }
    }
}])