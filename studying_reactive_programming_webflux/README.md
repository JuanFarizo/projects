# Mongo Documentation

[MongoDBDocumentation](https://www.mongodb.com/docs/manual/tutorial/install-mongodb-on-ubuntu/)

Directories
If you installed through the package manager, the data directory /var/lib/mongodb and the log directory /var/log/mongodb are created during the installation.

Configuration File
The official MongoDB package includes a configuration file (/etc/mongod.conf).

You can start the mongod process:

`sudo systemctl start mongod`

Verify that MongoDB has started successfully:

`sudo systemctl status mongod`

Stop MongoDB:

`sudo systemctl stop mongod`

Restart MongoDB:

`sudo systemctl restart mongod`

---

# Curl Commands

POST-CREATE-MOVIE-INFO
-----------------------
```
curl -i \
-d '{"movieInfoId":1, "name": "Batman Begins", "year":2005,"cast":["Christian Bale", "Michael Cane"],"release_date": "2005-06-15"}' \
-H "Content-Type: application/json" \
-X POST http://localhost:8080/v1/movieinfos
```

```
curl -i \
-d '{"movieInfoId":2, "name": "The Dark Knight", "year":2008,"cast":["Christian Bale", "HeathLedger"],"release_date": "2008-07-18"}' \
-H "Content-Type: application/json" \
-X POST http://localhost:8080/v1/movieinfos
```

```
curl -i \
-d '{"movieInfoId":null, "name": "Dark Knight Rises", "year":2012,"cast":["Christian Bale", "Tom Hardy"],"release_date": "2012-07-20"}' \
-H "Content-Type: application/json" \
-X POST http://localhost:8080/v1/movieinfos
```


GET-ALL-MOVIE-INFO
-----------------------
`curl -i http://localhost:8080/v1/movieinfos`

GET-MOVIE-INFO-BY-ID
-----------------------
`curl -i http://localhost:8080/v1/movieinfos/1`

GET-MOVIE-INFO-STREAM
-----------------------
`curl -i http://localhost:8080/v1/movieinfos/stream`

UPDATE-MOVIE-INFO
-----------------------
```
curl -i \
-d '{"movieInfoId":1, "name": "Batman Begins", "year":2005,"cast":["Christian Bale", "Michael Cane", "Liam Neeson"],"release_date": "2005-06-15"}' \
-H "Content-Type: application/json" \
-X PUT http://localhost:8080/v1/movieinfos/1
```

DELETE-MOVIE-INFO
-----------------------
`curl -i -X DELETE http://localhost:8080/v1/movieinfos/1`

STREAM-MOVIE-INFO
-----------------------
`curl -i http://localhost:8080/v1/movieinfos/stream`