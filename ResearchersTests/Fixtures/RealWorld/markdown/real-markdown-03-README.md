<!--
  Licensed to the Apache Software Foundation (ASF) under one
  or more contributor license agreements.  See the NOTICE file
  distributed with this work for additional information
  regarding copyright ownership.  The ASF licenses this file
  to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance
  with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing,
  software distributed under the License is distributed on an
  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
  KIND, either express or implied.  See the License for the
  specific language governing permissions and limitations
  under the License.
-->
# Apache Tika Server

See the [Apache Tika documentation](https://tika.apache.org/docs) (Using Tika &gt; Tika Server) for full usage.

Running
-------
```
$ java -jar tika-server/tika-server-standard/target/tika-server-standard-<version>.jar --help
   usage: tikaserver
    -?,--help           this help message
    -c,--config <arg>   tika-config file
    -h,--host <arg>     host name (default = localhost, use * for all)
    -i,--id <arg>       id for this server, written to the startup log
    -p,--port <arg>     listen port (default = 9998)
```

Everything beyond host, port and id is configured in the tika-config JSON file
passed with `-c`, not on the command line.
