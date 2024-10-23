### Mongo Documentation:

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
