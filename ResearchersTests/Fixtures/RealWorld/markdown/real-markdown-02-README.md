<!--
  Licensed to the Apache Software Foundation (ASF) under one or more
  contributor license agreements.  See the NOTICE file distributed with
  this work for additional information regarding copyright ownership.
  The ASF licenses this file to You under the Apache License, Version 2.0
  (the "License"); you may not use this file except in compliance with
  the License.  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
-->
# tika-metadata-schema

A machine-readable schema of Apache Tika's metadata keys, plus a registry-driven validator
(`MetadataKeyValidator`) that classifies any key as CLOSED / OPEN / TEMPLATE / UNKNOWN.

**Scope: `tika-core` + the standard parser bundle + the extended/optional families
(scientific, sqlite3, nlp, vlm; TIKA-4816 stage 5a).** All are on the (test-scope, for the
heavier ones) classpath, so `sqlite3:`, `vlm:`, `grib:`, `netcdf:`, `envi:`, `ctakes:`, `ner:`
and the `grobid:tei:*` keys are all in the registry. `MetadataCoverageTest` enforces completeness: any
module declaring keys that is neither scanned nor on its explicit out-of-scope list fails the
build, so nothing escapes *silently*. `OUT_OF_SCOPE` is currently empty; it stays as the documented
mechanism for excluding a future heavy/optional family.
