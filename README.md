# sql-server-utilities
Contains scripts and other tools for working with Microsoft SQL Server, specifically focused around automation of script writing.

# AbstractionGenerator
This script will write T-SQL database CRUD objects as well as an .edmx file for use with Entity Framework based on table definitions in a deployed database. You can read more about it at [Generating Abstraction Layers Automatically][].

# DataSampleScripter
This script will write a number of scripts to support getting sample data for testing. Because it recursively follows foreign keys for a provided table list, it will create INSERT statement wrappers for every table in a provided list and the tables those tables reference, until all foreign keys are satisfied. These INSERT statement wrappers are presented in dependency order, so the tables without dependencies come before the tables that depend on them, etc.

In addition to the INSERT statement wrappers, it also creates a "value generator script". This is a SELECT statement against every record in the table, writing its data into a VALUES element for the INSERT statements. The output of this script can be placed between the INSERT wrappers, and when the trailing comma in the values are removed, you have a valid INSERT statement*. 

It will also write a comprehensive series of DELETE statements in reverse-dependency order (the table with the most parent references first) to support data cleanup in a test environment. You can customize the WHERE clauses in the value generators and DELETE statments to target specific data of interest in your production systems, and provided you have SELECT permissions, you can easily create re-usable, re-runnable data generation scripts for unit tests. Further, you could extend the value generator script generation to automatically obscure certain fields (e.g., social security numbers and other PII) if you have standardized field names on which to rely. This can help avoid embarrassing issues with auditors.

* Valid so long as there are 1000 or fewer VALUES elements specified, as that is the upper limit for SQL Server.


[Generating Abstraction Layers Automatically]: https://sqlemil.wordpress.com/2015/12/31/generating-abstraction-layers-automatically/
