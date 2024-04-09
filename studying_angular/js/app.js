(function() {
    var app = angular.module('universidadApp', []);

    var profesordData = {
        nombre: "Pepe trueno",
        bio: "No se que soy una mezcla de vaca raton",
        edad: 47,
        foto: "img/images.jpg"
    }
    
    app.controller('profesorCtrl', function ($scope) {
        $scope.profesor = profesordData;
        $scope.editando = {};
        $scope.mostrarCaja = false;
    
        $scope.editarProfesor = function () {
            angular.copy( $scope.profesor, $scope.editando);
            $scope.mostrarCaja = true;
        }
    
        $scope.guardarCambios = function() {
            angular.copy($scope.editando, $scope.profesor);
            $scope.mostrarCaja = false;
        }
    
        $scope.cancelarCambios = function () {
            $scope.editando = {};
            $scope.mostrarCaja = false;
        }
    });
    
    app.controller('listadoCtrl', ['$scope', function ($scope) {
        $scope.listado = ["pepe", "juan", "jhon"]
        $scope.listadoProfesores = {
            profesores: [
                {
                    nombre: "Pis",
                    edad: 66,
                    clase: "mear"
                },
                {
                    nombre: "caca",
                    edad: 67,
                    clase: "cagar"
                },
                {
                    nombre: "tos",
                    edad: 656,
                    clase: "toser"
                }
            ]
        };

        $scope.personas = [{
            "id": 1,
            "sexo": "Female",
            "nombre": "Merissa",
            "avatar": "http://dummyimage.com/160x100.png/5fa2dd/ffffff",
            "telefono": "569-700-5251",
            "celular": "222-750-9867"
          }, {
            "id": 2,
            "sexo": "Female",
            "nombre": "Mersey",
            "avatar": "http://dummyimage.com/169x100.png/cc0000/ffffff",
            "telefono": "113-768-2199",
            "celular": "363-677-7048"
          }, {
            "id": 3,
            "sexo": "Male",
            "nombre": "Edmund",
            "avatar": "http://dummyimage.com/201x100.png/cc0000/ffffff",
            "telefono": "948-297-3211",
            "celular": "679-770-0004"
          }, {
            "id": 4,
            "sexo": "Male",
            "nombre": "Araldo",
            "avatar": "http://dummyimage.com/222x100.png/cc0000/ffffff",
            "telefono": "955-725-6464",
            "celular": "423-983-6499"
          }, {
            "id": 5,
            "sexo": "Female",
            "nombre": "Moselle",
            "avatar": "http://dummyimage.com/128x100.png/5fa2dd/ffffff",
            "telefono": "316-130-1167",
            "celular": "819-981-4205"
          }, {
            "id": 6,
            "sexo": "Polygender",
            "nombre": "Cole",
            "avatar": "http://dummyimage.com/138x100.png/5fa2dd/ffffff",
            "telefono": "481-531-1399",
            "celular": "707-752-9246"
          }, {
            "id": 7,
            "sexo": "Male",
            "nombre": "Foster",
            "avatar": "http://dummyimage.com/134x100.png/dddddd/000000",
            "telefono": "485-428-1614",
            "celular": "436-774-0051"
          }, {
            "id": 8,
            "sexo": "Male",
            "nombre": "Curr",
            "avatar": "http://dummyimage.com/227x100.png/cc0000/ffffff",
            "telefono": "479-831-5401",
            "celular": "935-579-0687"
          }, {
            "id": 9,
            "sexo": "Genderfluid",
            "nombre": "Lanie",
            "avatar": "http://dummyimage.com/180x100.png/cc0000/ffffff",
            "telefono": "422-860-8118",
            "celular": "116-312-2426"
          }, {
            "id": 10,
            "sexo": "Male",
            "nombre": "Yankee",
            "avatar": "http://dummyimage.com/125x100.png/ff4444/ffffff",
            "telefono": "533-872-7712",
            "celular": "456-373-4523"
          }, {
            "id": 11,
            "sexo": "Male",
            "nombre": "Gabriele",
            "avatar": "http://dummyimage.com/165x100.png/dddddd/000000",
            "telefono": "757-407-3102",
            "celular": "765-793-0494"
          }, {
            "id": 12,
            "sexo": "Male",
            "nombre": "Alleyn",
            "avatar": "http://dummyimage.com/134x100.png/dddddd/000000",
            "telefono": "358-552-2193",
            "celular": "296-717-5190"
          }, {
            "id": 13,
            "sexo": "Male",
            "nombre": "Colet",
            "avatar": "http://dummyimage.com/201x100.png/5fa2dd/ffffff",
            "telefono": "474-277-7949",
            "celular": "842-561-0957"
          }, {
            "id": 14,
            "sexo": "Male",
            "nombre": "Alvy",
            "avatar": "http://dummyimage.com/221x100.png/ff4444/ffffff",
            "telefono": "195-578-0248",
            "celular": "824-786-2745"
          }, {
            "id": 15,
            "sexo": "Female",
            "nombre": "Linnell",
            "avatar": "http://dummyimage.com/178x100.png/cc0000/ffffff",
            "telefono": "832-342-4962",
            "celular": "519-466-0729"
          }, {
            "id": 16,
            "sexo": "Agender",
            "nombre": "Ruperta",
            "avatar": "http://dummyimage.com/167x100.png/cc0000/ffffff",
            "telefono": "671-198-9931",
            "celular": "706-268-4955"
          }, {
            "id": 17,
            "sexo": "Male",
            "nombre": "Bailey",
            "avatar": "http://dummyimage.com/165x100.png/ff4444/ffffff",
            "telefono": "826-212-7258",
            "celular": "931-649-2466"
          }, {
            "id": 18,
            "sexo": "Female",
            "nombre": "Emelina",
            "avatar": "http://dummyimage.com/133x100.png/ff4444/ffffff",
            "telefono": "598-342-8193",
            "celular": "737-172-4717"
          }, {
            "id": 19,
            "sexo": "Genderfluid",
            "nombre": "Jean",
            "avatar": "http://dummyimage.com/139x100.png/dddddd/000000",
            "telefono": "581-901-0964",
            "celular": "658-213-0740"
          }, {
            "id": 20,
            "sexo": "Female",
            "nombre": "Luise",
            "avatar": "http://dummyimage.com/179x100.png/ff4444/ffffff",
            "telefono": "261-959-3660",
            "celular": "850-362-7243"
          }];

          $scope.paisSeleccionado = "";

          $scope.paises = [{
            "id": "ID",
            "nombre": "Indonesia"
          }, {
            "id": "PH",
            "nombre": "Philippines"
          }, {
            "id": "TL",
            "nombre": "East Timor"
          }, {
            "id": "BD",
            "nombre": "Bangladesh"
          }, {
            "id": "US",
            "nombre": "United States"
          }, {
            "id": "NI",
            "nombre": "Nicaragua"
          }, {
            "id": "KZ",
            "nombre": "Kazakhstan"
          }, {
            "id": "CO",
            "nombre": "Colombia"
          }, {
            "id": "SV",
            "nombre": "El Salvador"
          }, {
            "id": "AL",
            "nombre": "Albania"
          }, {
            "id": "CN",
            "nombre": "China"
          }, {
            "id": "AR",
            "nombre": "Argentina"
          }, {
            "id": "ID",
            "nombre": "Indonesia"
          }, {
            "id": "MX",
            "nombre": "Mexico"
          }, {
            "id": "RU",
            "nombre": "Russia"
          }, {
            "id": "RS",
            "nombre": "Serbia"
          }, {
            "id": "PH",
            "nombre": "Philippines"
          }, {
            "id": "RU",
            "nombre": "Russia"
          }, {
            "id": "CN",
            "nombre": "China"
          }, {
            "id": "BR",
            "nombre": "Brazil"
          }];
    }]);


    app.controller('mainCtrl', ['$scope','$http', function($scope,$http){
      $scope.profesores = {};
      $scope.tblProfesores= 'parciales/tblProfesores.html'
    
      $http.get('json/profesores.json').success(function (data) {
        $scope.profesores = data.profesores;
      });
      
    
     /* $http.get('json/profesores.json').then(function (data) {
        $scope.profesores = data;
      });
    */
    
    }]);



})();

