set ansi_nulls, nocount on;

--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- Set execution parameters
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- This is used to tell Entity Framework what version of SQL Server it's dealing with in the SSDL. All indications
-- are that the "friendly" identifiers are used: e.g., 2012, 2014, 2008R2, etc.
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 declare @sqlServerVersionToken nvarchar(10) = N'2012',
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- This sets the schema name into which the database abstraction objects will be placed
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        @databaseAbstractionSchema nvarchar(128) = N'DAL',
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- This bit toggles whether or not a check is added to update and delete procedures to throw an error if the
-- target record does not exist in the target table.
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        @includeTargetRecordCheck bit = CAST(1 as bit), -- 0 = do not validate target exists, 1 = validate target exists
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- This bit toggles whether or not checks are added to insert, update, and delete procedures to throw an error if
-- parent values for foreign key columns cannot be found.
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        @includeKeyValidationCheck bit = CAST(1 as bit), -- 0 = do not validate references, 1 = validate references
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- This bit toggles whether or not debug messages are printed during execution.
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        @debugMode bit = CAST(0 as bit), -- 0 = off, 1 = on
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- This bit toggles whether or not the demo is run. Demo requires CREATE SCHEMA and CREATE TABLE rights in the
-- database of execution. PLEASE DO NOT RUN THE DEMO IN A PRODUCTION ENVIRONMENT!
-- Demo mode will drop the objects it creates (including the schema) at the end of the script.
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        @demoMode bit = CAST(0 as bit); -- 0 = off, 1 = on
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- Declare table list
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
declare @tableListSubmitted table (
    [schemaQualifiedObjectName] nvarchar(128)   null
    );

insert @tableListSubmitted ( [schemaQualifiedObjectName] )
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- Add all the tables over which you'd like to generate abstraction as ( 'schemaName.tableName' )
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
values  ('')
        ;

--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- Declare parameter exclusion list
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
declare @insertParameterExcludedColumns table (
    [name]  nvarchar(128)
    );

declare @updateParameterExcludedColumns table (
    [name]  nvarchar(128)
    );

insert @insertParameterExcludedColumns
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- Add audit columns or other columns populated by default or not to be exposed to the application for CREATION
-- of new records here. This will apply to ALL tables!
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
values  (N'')
        ;

insert @updateParameterExcludedColumns
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- Add audit columns or other columns populated by default or not to be exposed to the application for UPDATE
-- of existing records here. This will apply to ALL tables!
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
values  (N'')
        ;

--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- Here on down is the guts of the code. If you just want to let things roll, no need to read further
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
declare @objectId                           int,
        @columnId                           int,
        @schemaName                         nvarchar(128),
        @objectName                         nvarchar(128),
        @quotedSchemaQualifiedName          nvarchar(261), -- two sysnames, four brackets, and a period
        @isEverFkParent                     bit,
        @isEverFkChild                      bit,
        @isReadOnly                         bit, -- indicates if table was added for FK support and should be exposed read-only
        @coveringViewName                   nvarchar(128),
        @insertProcName                     nvarchar(128),
        @updateProcName                     nvarchar(128),
        @deleteProcName                     nvarchar(128),
        @columnName                         nvarchar(128),
        @indexColumnId                      int,
        @hasIdentityFlag                    tinyint,
        @identityColumnId                   int,
        @lineEnd                            nchar(2)        = CHAR(13) + CHAR(10),
        @tab                                nchar(1)        = CHAR(9), -- Used in .edmx file for normal XML formatting
        @tabSpace                           nchar(4)        = N'    ', -- Used in SQL scripts, as tabs can lead to weird presentation issues
        @xmlElementClose                    nvarchar(3)     = N' />',
        @databaseName                       nvarchar(128)   = DB_NAME(),
        @dependencyGroupCounter             int, -- used to count dependency depth
        @ssdlEntityContainer                nvarchar(max), -- holds CSDL EntityContainer definition
        @csdlEntityContainer                nvarchar(max), -- holds CSDL EntityContainer definition
        @targetWhereClause                  nvarchar(max), -- holds WHERE clause used in UPDATE and DELETE procs
        @targetRecordCheck                  nvarchar(max), -- holds check for target record used in UPDATE and DELETE procs
        @fkName                             nvarchar(128), -- when stepping through FK's, name of current FK
        @isCurrentTableParent               bit, -- when stepping through FK's, indicates if current table is parent of current FK
        @fkObjectId                         int, -- when stepping through FK's, object_id of current FK
        @fkParentObjectId                   int, -- when stepping through FK's, referenced_object_id of current FK
        @fkParentName                       nvarchar(128), -- when stepping through FK's, unquoted, non-qualified name of referenced_object_id object
        @fkParentQuotedSchemaQualifiedName  nvarchar(261), -- when stepping through FK's, quoted, schema-qualified name of referenced_object_id of current FK
        @fkChildObjectId                    int, -- when stepping through FK's, parent_object_id of current FK
        @fkChildName                        nvarchar(128), -- when stepping through FK's, unquoted, non-qualified name of parent_object_id object
        @fkChildQuotedSchemaQualifiedName   nvarchar(261), -- when stepping through FK's, quoted, schema-qualified name of parent_object_id of current FK
        @thisKeyValidationCheckWhereClause  nvarchar(max), -- when stepping through FK's, holds WHERE clause for current key validation check
        @fkColumnId                         int, -- when stepping through FK columns, constraint_column_id of column
        @thisParentColumnName               nvarchar(128),
        @thisChildColumnName                nvarchar(128),
        @keyValidationCheck                 nvarchar(max), -- holds checks for parent keys for FK reference values
        @deleteKeyValidationCheck           nvarchar(max), -- holds checks for child keys for FK reference values
        @coveringView                       nvarchar(max), -- script to create covering view
        @createProc                         nvarchar(max), -- script to create INSERT proc
        @updateProc                         nvarchar(max), -- script to create UPDATE proc
        @deleteProc                         nvarchar(max), -- script to create DELETE proc
        @thisSsdlEntityType                 nvarchar(max), -- holds SSDL EntityType definition for current table
        @thisSsdlEntitySet                  nvarchar(max), -- holds SSDL EntitySet definition for current table
        @thisCsdlEntityType                 nvarchar(max), -- holds CSDL EntityType definition for current table
        @thisCsdlEntitySet                  nvarchar(max), -- holds CSDL EntitySet definition for current table
        @thisMslEntitySetMapping            nvarchar(max), -- holds MSL EntitySetMapping definition for current table
        @thisSsdlAssociation                nvarchar(max), -- holds SSDL Association definitions for current table
        @thisSsdlAssociationSet             nvarchar(max), -- holds SSDL AssociationSet definitions for current table
        @thisCsdlAssociation                nvarchar(max), -- holds CSDL Association definitions for current table
        @thisCsdlAssociationSet             nvarchar(max), -- holds CSDL AssociationSet definitions for current table
        @thisCsdlNavigationProperties       nvarchar(max), -- holds CSDL NavigationProperty definitions for current table
        @thisSsdlFunction                   nvarchar(max), -- holds SSDL Function definition for current procedure
        @ssdlEntityTypes                    nvarchar(max)   = N'', -- holds all SSDL EntityType definitions
        @ssdlEntitySets                     nvarchar(max)   = N'', -- holds all SSDL EntitySet definitions
        @csdlEntityTypes                    nvarchar(max)   = N'', -- holds all CSDL EntityType definitions
        @csdlEntitySets                     nvarchar(max)   = N'', -- holds all CSDL EntitySet definitions
        @ssdlAssociations                   nvarchar(max)   = N'', -- holds all SSDL Association definitions
        @ssdlAssociationSets                nvarchar(max)   = N'', -- holds all SSDL AssociationSet definitions
        @csdlAssociations                   nvarchar(max)   = N'', -- holds all CSDL Association definitions
        @csdlAssociationSets                nvarchar(max)   = N'', -- holds all CSDL AssociationSet definitions
        @ssdlFunctions                      nvarchar(max)   = N'', -- holds all SSDL Function definitions
        @mslEntitySetMappings               nvarchar(max)   = N'', -- holds all MSL EntitySetMapping definitions
        @edmxPresentationStatement          nvarchar(max)   = N'', -- holds .edmx file for final return
        @executionStart                     datetime2(7)    = SYSUTCDATETIME(),
        @executionEnd                       datetime2(7);

-- holds all SQL objects for final return
-- We can already make a few assumptions about content, so we get it started off right away.
declare @crudPresentationStatement  nvarchar(max)   =   N'-- These CRUD objects were automatically generated based on table definitions in '
                                                        + @databaseName
                                                        + N' on '
                                                        + @@SERVERNAME
                                                        + N' as of '
                                                        + CONVERT(nvarchar(27), @executionStart, 121)
                                                        + N' UTC by '
                                                        + ORIGINAL_LOGIN()
                                                        + N'.'
                                                        --
                                                        + @lineEnd
                                                        --
                                                        + @lineEnd
                                                        + N'-- This schema holds abstraction objects for application interface'
                                                        --
                                                        + @lineEnd
                                                        + N'CREATE SCHEMA '
                                                        + QUOTENAME(@databaseAbstractionSchema, N'[')
                                                        + N' AUTHORIZATION [dbo];'
                                                        --
                                                        + @lineEnd
                                                        + N'GO'
                                                        + @lineEnd;

-- A similar statement is added to the @edmsPresentationStatement when it is assembled at the end of the script.

if @demoMode = CAST(1 as bit)
begin;
    select [DemoModeEngaged] = N'!!! DEMO MODE ENGAGED !!!'
    print   N'!!!!!!!!!!!!!!!!!!!!!!!!!'
            + N'!!! DEMO MODE ENGAGED !!!'
            + N'!!!!!!!!!!!!!!!!!!!!!!!!!';

    -- Here is a simple set of test tables to use to prove the multi-member key handling and external reference
    -- functions work and demonstrate the general output of the script. Some of the naming follows practices I
    -- would normally avoid as a tradeoff for a clearer (and more easily assembled) example.
    if SCHEMA_ID(N'abstractionDemo') is null
    begin;
        print N'Creating abstractionDemo schema...';
        execute ( N'create schema [abstractionDemo] authorization [dbo];' );
        print N'...done!';
    end;
    else begin;
        print N'abstractionDemo schema already exists.';
    end;
    
    if OBJECT_ID(N'abstractionDemo.twoMemberPk', N'U') is null
    begin;
        print N'Creating table [abstractionDemo].[twoMemberPk]...';
        create table [abstractionDemo].[twoMemberPk] (
            -- Exact Numerics
            [colBigintPk]           bigint              identity(1, 1) not null,
            [colBit]                bit                 null,
            [colDecimal]            decimal(18, 6)      null,
            [colIntPk]              int                 not null,
            [colMoney]              money               null, -- please don't use MONEY, it is weird and unnecessary, this is just to prove compatibility
            [colNumeric]            numeric(8, 7)       null,
            [colSmallint]           smallint            null,
            [colSmallmoney]         smallmoney          null, -- please don't use SMALLMONEY, it is weird and unnecessary, this is just to prove compatibility
            [colTinyint]            tinyint             null,
            -- Approximate Numerics
            [colFloat]              float(42)           null, -- please don't use FLOAT, it is undeterministic, this is just to prove compatibility
            [colReal]               real                null, -- please don't use REAL, it is undeterministic, this is just to prove compatibility
            -- Date and Time
            [colDate]               date                null,
            [colDatetime2]          datetime2           null,
            [colDatetime]           datetime            null, -- please don't use DATETIME, it is deprecated (https://msdn.microsoft.com/en-us/library/ms187819.aspx), this is just to prove compatibility
            [colDatetimeoffset]     datetimeoffset      null,
            [colSmalldatetime]      smalldatetime       null, -- please don't use SMALLDATETIME, it is deprecated (https://msdn.microsoft.com/en-us/library/ms182418.aspx), this is just to prove compatibility
            [colTime]               time                null,
            -- Character Strings
            [colChar]               char(5)             null,
            [colText]               text                null, -- please don't use TEXT, it is deprecated (https://msdn.microsoft.com/en-us/library/ms187993.aspx), this is just to prove compatibility
            [colVarchar]            varchar(5)          null,
            -- Unicode Character Strings
            [colNchar]              nchar(5)            null,
            [colNtext]              ntext               null, -- please don't use NTEXT, it is deprecated (https://msdn.microsoft.com/en-us/library/ms187993.aspx), this is just to prove compatibility
            [colNvarchar]           nvarchar(5)         null,
            [colNvarcharMax]        nvarchar(max)       null,
            -- Binary Strings
            [colBinary]             binary(5)           null,
            [colImage]              image               null, -- please don't use IMAGE, it is deprecated (https://msdn.microsoft.com/en-us/library/ms187993.aspx), this is just to prove compatibility
            [colVarbinaryMax]       varbinary(max)      null, -- You really probably don't want to do this, you'd rather store a file path or other pointer, this is just to prove compatibility
            -- Other Data Types
            [colHierarchyid]        hierarchyid         null, -- HIERARCHYID isn't supported in Entity Framework, so the scripting "works" but EF will break trying to use it
            [colTimestamp]          rowversion          null, -- see https://msdn.microsoft.com/en-us/library/ms182776%28v=sql.110%29.aspx
            [colUniqueidentifier]   uniqueidentifier    null,
            [colXml]                xml                 null,
            [colGeography]          geography           null,
            [colGeometry]           geometry            null,
            constraint [PK_twoMemberPk] primary key clustered ( [colBigintPk], [colIntPk] )
            );
        print N'...done!';
    end;
    else begin;
        print N'[abstractionDemo].[twoMemberPk] already exists.';
    end;
    
    if OBJECT_ID(N'abstractionDemo.externalReference', N'U') is null
    begin;
        print N'Creating table [abstractionDemo].[externalReference]...';
        create table [abstractionDemo].[externalReference] (
            [Id]    int             identity(1,1) not null,
            [Label] nvarchar(10)    not null,
            constraint [PK_externalReference] primary key clustered ( [Id] )
            );
        print N'...done!';
    end;
    else begin;
        print N'[abstractionDemo].[externalReference] already exists.';
    end;
    
    if OBJECT_ID(N'abstractionDemo.twoMemberFk', N'U') is null
    begin;
        print N'Creating table [abstractionDemo].[twoMemberFk]...';
        create table [abstractionDemo].[twoMemberFk] (
            [Id]                    int             identity(1, 1) not null,
            [colBigintFk]           bigint          not null,
            [colIntFk]              int             not null,
            [externalReferenceId]   int             not null,
            [HistoricUid]           bigint          null, -- this would normally be populated by a NEXT VALUE FOR default
            [Created]               datetime2       not null constraint [DF_twoMemberFk_Created] default (SYSUTCDATETIME()),
            [CreatedBy]             nvarchar(128)   not null constraint [DF_twoMemberFk_CreatedBy] default (ORIGINAL_LOGIN()),
            [Updated]               datetime2       not null constraint [DF_twoMemberFk_Updated] default (SYSUTCDATETIME()),
            [UpdatedBy]             nvarchar(128)   not null constraint [DF_twoMemberFk_UpdatedBy] default (ORIGINAL_LOGIN()),
            constraint [PK_twoMemberFk] primary key clustered ( [Id] ),
            constraint [FK_twoMemberFk_twoMemberPk_colBigintFk_colIntFk] foreign key ( [colBigintFk], [colIntFk] ) references [abstractionDemo].[twoMemberPk] ( [colBigintPk], [colIntPk] ),
            constraint [FK_twoMemberFk_externalReference_externalReferenceId] foreign key ( [externalReferenceId] ) references [abstractionDemo].[externalReference] ( [Id] )
            );
        print N'...done!';
    end;
    else begin;
        print N'[abstractionDemo].[twoMemberFk] already exists.';
    end;
    
    print N'Emptying input tables (@insertParameterExcludedColumns, @updateParameterExcludedColumns, and @tableListSubmitted)...'
    delete @insertParameterExcludedColumns;
    delete @updateParameterExcludedColumns;
    delete @tableListSubmitted;
    print N'...done!'

    print N'Setting up demo data...';
    insert @insertParameterExcludedColumns
    values  (N'HistoricUid'),
            (N'Created'),
            (N'Updated'),
            (N'UpdatedBy');
    
    insert @updateParameterExcludedColumns
    values  (N'HistoricUid'),
            (N'Created'),
            (N'CreatedBy'),
            (N'Updated');

    insert @tableListSubmitted ( [schemaQualifiedObjectName] )
    values  (N'abstractionDemo.twoMemberPk'),
            (N'abstractionDemo.twoMemberFk');
    print N'...done!'
end;

print N'AbstractionGenerator script execution start: ' + CONVERT(nvarchar(27), @executionStart, 121) + N' UTC.';

declare @columnInfo table (
    [columnId]              int             not null,
    [name]                  nvarchar(128)   not null,
    [dbType]                nvarchar(128)   not null,
    [appType]               nvarchar(128)   not null,
    [maxLength]             nvarchar(11)    null, -- value one would use writing type, not raw value from sys.columns; string because we'll concatenate it
    [isFixedLength]         nvarchar(5)     null, -- indicates if column width is invariant (char vs varchar), stored as string boolean for ease of use
    [precision]             nvarchar(11)    null, -- string because we'll concatenate it
    [scale]                 nvarchar(11)    null, -- string because we'll concatenate it
    [isUnicode]             nvarchar(5)     null, -- indicates if column stores a unicode string, stored as string boolean for ease of use
    [isNullable]            nvarchar(5)     null, -- indicates if column accepts NULL values, stored as string boolean for ease of use
    [isIdentity]            nvarchar(5)     null, -- indicates if column is populated by the database as an identity, stored as string boolean for ease of use
    [isCalculated]          nvarchar(5)     null, -- indicates if column is populated by the database and should not be inserted by the DAL, stored as string boolean for ease of use
    [pkIndexId]             int             null, -- if not null, index id of the column in the PK index
    [isFkParent]            bit             null, -- indicates if column is referenced by foreign key constraint in child table in table list
    [isFkChild]             bit             null, -- indicates if column is subject to foreign key constraint
    [isInsertParameter]     bit             null, -- indicates if column should be used as a parameter in the INSERT proc
    [isUpdateParameter]     bit             null, -- indicates if column should be used as a parameter in the UPDATE proc
    [isDeleteParameter]     bit             null -- indicates if column should be used as a parameter in the DELETE proc
    );

-- Used to construct WHERE clause
declare @primaryKeyColumns table (
    [columnName]    nvarchar(128)   null,
    [indexColumnId] int             null
    );

declare @foreignKeyInfo table (
    [foreignKeyName]                    nvarchar(128)   not null,
    [foreignKeyObjectId]                int             not null,
    [isCurrentTableParent]              bit             not null,
    [parentObjectId]                    int             not null,
    [parentName]                        nvarchar(128)   not null,
    [parentQuotedSchemaQualifiedName]   nvarchar(261)   not null,
    [childObjectId]                     int             not null,
    [childName]                         nvarchar(128)   not null,
    [childQuotedSchemaQualifiedName]    nvarchar(261)   not null,
    [fkColumnId]                        int             not null,
    [parentColumnName]                  nvarchar(128)   not null,
    [childColumnName]                   nvarchar(128)   not null
    );

--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- Validate and order table list
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
declare @tableListPresented table (
    [quotedSchemaQualifiedName] nvarchar(261)	null,
    [name]                      nvarchar(128)   null,
    [objectId]					int				null,
    [isFkParent]                tinyint         null, -- this tells us we'll need to create an association for the table
    [isFkChild]                 tinyint         null, -- this tells us we'll need key validation checks for a table
    [isAddedForFk]              tinyint         null, -- indicates if a table was added for FK information
    [dependencyGroup]           tinyint         null, -- this represents the set of tables at a particular depth in the dependency chain
    -- Object names need to get referenced in the .edmx content in addition to the SQL objects, so we'll generate
    -- the names once to use repeatedly
    [coveringViewName]          nvarchar(128)   null,
    [insertProcName]            nvarchar(128)   null,
    [updateProcName]            nvarchar(128)   null,
    [deleteProcName]            nvarchar(128)   null
    );

insert @tableListPresented (
    [quotedSchemaQualifiedName],
    [objectId],
    [coveringViewName],
    [insertProcName],
    [updateProcName],
    [deleteProcName]
    )
select  [quotedSchemaQualifiedName] =   QUOTENAME(SCHEMA_NAME([schema_id]), '[')
                                        + N'.'
                                        + QUOTENAME([name], '['),
        [objectId]                  =   [object_id],
        [coveringViewName]          =   N'vw' + [name],
        [insertProcName]            =   [name] + N'Create',
        [updateProcName]            =   [name] + N'Update',
        [deleteProcName]            =   [name] + N'Delete'
from    @tableListSubmitted
        inner join
        -- This OBJECT_ID() call insures we only bring through tables
        sys.objects on objects.[object_id] = OBJECT_ID([schemaQualifiedObjectName], 'U');

---------------------------------------------------------------------------------------------------------------------
-- A NOTE ON sys.foreign_keys NAMING:
-- A foreign key's parent object is the table on which the foreign key is defined. However, from the perspective
-- of the foreign key, the parent object is the CHILD table, because it is referencing the table specified by the
-- [referenced_object_id] value.
---------------------------------------------------------------------------------------------------------------------

-- Determine if tables have any foreign keys. If so, make sure the referenced tables are added to the list, and do
-- so recursively. Having all parent tables in the @tableListPresent set makes calculating dependency groups far
-- simpler, so until there is a better method for handling that, this is the easiest path.
while exists (  select  *
                from    @tableListPresented
                        inner join
                        [sys].[foreign_keys] on [foreign_keys].[parent_object_id] = [objectId]
                where   not exists ( select 1 from @tableListPresented where [objectId] = [foreign_keys].[referenced_object_id] )
              )
begin;
    -- We set the isFkParent because we want to create associations to these tables for read-only access
    insert @tableListPresented (
        [quotedSchemaQualifiedName],
        [objectId],
        [isAddedForFk],
        [isFkParent],
        [coveringViewName]
        )
    -- We need to use SELECT DISTINCT to avoid adding the same table twice if another table has more
    -- than one foreign key referencing it.
    select distinct [schemaQualifiedObjectName] =   QUOTENAME(OBJECT_SCHEMA_NAME([foreign_keys].[referenced_object_id]), '[')
                                                    + N'.' 
                                                    +  QUOTENAME(OBJECT_NAME([foreign_keys].[referenced_object_id]), '['),
                    [foreign_keys].[referenced_object_id],
                    [isAddedForFk]              = 1,
                    [isFkParent]                = 1,
                    [coveringViewName]          = N'vw' + OBJECT_NAME([foreign_keys].[referenced_object_id])
    from    [sys].[foreign_keys]
            inner join
            @tableListPresented on objectId = [foreign_keys].[parent_object_id]
    where   not exists ( select 1 from @tableListPresented where [objectId] = [foreign_keys].[referenced_object_id] );
end;

-- Determine if table is parent of a foreign key whose child is also in the table list. This drives the creation
-- of associations in the .edmx file.
if exists ( select * from @tableListPresented where [isFkParent] is null )
begin;
    
    -- Mark all the referenced tables
    update  @tableListPresented
    set     [isFkParent] = 1
    where   exists (    select  *
                        from    [sys].[foreign_keys]
                        where   [foreign_keys].[referenced_object_id] = [objectId]
                                and
                                [foreign_keys].[parent_object_id] in ( select [objectId] from @tableListPresented )
                   )
            and
            -- We have already handled tables added for FK navigation, so the only remaining NULLs are those we
            -- want to evaluate.
            [isFkParent] is null;

    -- By definition, every record left with NULL is not referenced
    update  @tableListPresented
    set     [isFkParent]    = 0
    where   [isFkParent] is null;

end;

-- Determine if table is child of a foreign key.
if exists ( select * from @tableListPresented where [isFkChild] is null )
begin;
    
    -- Mark all the FK parent tables
    update  @tableListPresented
    set     [isFkChild] = 1
    where   exists (    select  *
                        from    [sys].[foreign_keys]
                        where   [foreign_keys].[parent_object_id] = [objectId]
                   )
            and
            [isFkChild] is null;

    -- By definition, every record left with NULL is not an FK child
    update  @tableListPresented
    set     [isFkChild] = 0
    where   [isFkChild] is null;

end;

-- Initialize dependency group counter and determine dependency groups
set @dependencyGroupCounter = 0;

-- If a table is not the child of any foreign key, then it is in dependency group 0.
update  @tableListPresented
set     [dependencyGroup] = @dependencyGroupCounter
where   [isFkChild] = 0;

while exists ( select * from @tableListPresented where [dependencyGroup] is null )
begin;
    
    -- Increment dependency group
    set @dependencyGroupCounter = @dependencyGroupCounter + 1;

    -- Identify group membership
    update  @tableListPresented
    set     [dependencyGroup] = @dependencyGroupCounter
    from    @tableListPresented
    where   [dependencyGroup] is null
            and
            (
                -- This makes sure that all of the given table's parent tables ([referenced_object_id]) already
                -- have a dependency group.
                not exists (    
                                select  [referenced_object_id]
                                from    [sys].[foreign_keys]
                                where   [foreign_keys].[parent_object_id] = [objectId]

                                except

                                select  [objectId]
                                from    @tableListPresented
                                where   [dependencyGroup] is not null
                           )
                or
                -- This handles tables with self-referencing foreign keys
                exists  (
                            select  1
                            from    [sys].[foreign_keys]
                            where   [foreign_keys].[parent_object_id] = [foreign_keys].[referenced_object_id]
                                    and
                                    [foreign_keys].[parent_object_id] = [objectId]
                        )
            );

end;

if @debugMode = CAST(1 as bit)
begin;
    select N'@tableListPresented after preparation:'
    select * from @tableListPresented;
end;

--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- For each table...
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
declare [tableCursor] cursor 
    for select      [objectId],
                    [quotedSchemaQualifiedName],
                    [isFkParent],
                    [isFkChild],
                    [isReadOnly]    =   case
                                            when [isAddedForFk] = 1
                                                then CAST(1 as bit)
                                            else CAST(0 as bit)
                                        end,
                    [coveringViewName],
                    [insertProcName],
                    [updateProcName],
                    [deleteProcName]
        from        @tableListPresented
        where       [objectId] is not null
        order by    [dependencyGroup],
                    [quotedSchemaQualifiedName];

open [tableCursor];

fetch next from [tableCursor]
into @objectId, @quotedSchemaQualifiedName, @isEverFkParent, @isEverFkChild, @isReadOnly, @coveringViewName, @insertProcName, @updateProcName, @deleteProcName;

while @@FETCH_STATUS = 0
begin;
    
    if @debugMode = CAST(1 as bit)
    begin;
        select  [tableName] = @quotedSchemaQualifiedName;
    end;

    -- Initialize the wrapper values and identity flag to avoid old values persisting
    -- across iterations and avoid NULL concatenation issues.
    select  @objectName                     = OBJECT_NAME(@objectId),
            @schemaName                     = OBJECT_SCHEMA_NAME(@objectId),
            @hasIdentityFlag                = 0,
            @targetWhereClause              = N'',
            @targetRecordCheck              = N'',
            @keyValidationCheck             = N'',
            @deleteKeyValidationCheck       = N'',
            @coveringView                   = N'',
            @createProc                     = N'',
            @updateProc                     = N'',
            @deleteProc                     = N'',
            @thisSsdlAssociation            = N'',
            @thisSsdlAssociationSet         = N'',
            @thisCsdlAssociation            = N'',
            @thisCsdlAssociationSet         = N'',
            @thisSsdlEntityType             = N'',
            @thisSsdlEntitySet              = N'',
            @thisCsdlEntityType             = N'',
            @thisCsdlEntitySet              = N'',
            @thisMslEntitySetMapping        = N'',
            @thisSsdlFunction               = N'',
            @thisCsdlNavigationProperties   = N'';

--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- ...Populate column info for table
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    -- Because we need the column info all over the place, we gather it and a bunch of metadata about it before we do
    -- anything else with the table. This helps keep logic about the columns in one place.
    delete @columnInfo;

    insert @columnInfo (
        [columnId],
        [name],
        [dbType],
        [appType],
        [maxLength],
        [isFixedLength],
        [precision],
        [scale],
        [isUnicode],
        [isNullable],
        [isIdentity],
        [isCalculated]
        )
    select  [columnId]      = [columns].[column_id],
            [name]          = [columns].[name],
            [dbType]        = [types].[name],
            [appType]       = case
                                when [types].[name] = N'bigint'
                                    then N'Int64'
                                when [types].[name] = N'bit'
                                    then N'Boolean'
                                when [types].[name] = N'int'
                                    then N'Int32'
                                when [types].[name] in ( N'decimal', N'money', N'numeric', N'smallmoney' )
                                    then N'Decimal'
                                when [types].[name] = N'real'
                                     or
                                     (
                                        [types].[name] = N'float'
                                        and
                                        [columns].[precision] <= 24
                                     )
                                    then N'Single'
                                when [types].[name] = N'float' -- any remaining must have [precision] > 24
                                    then N'Double'
                                when [types].[name] in ( N'date', N'datetime2', N'datetime', N'smalldatetime' )
                                    then N'DateTime'
                                when [types].[name] = N'datetimeoffset'
                                    then N'DateTimeOffset'
                                when [types].[name] = N'time'
                                    then N'Time'
                                when [types].[name] in ( N'char', N'text', N'varchar', N'nchar', N'ntext', N'nvarchar', N'xml' )
                                    then N'String'
                                when [types].[name] in ( N'binary', N'image', N'varbinarymax', N'timestamp', N'rowversion' )
                                    then N'Binary'
                                when [types].[name] = N'uniqueidentifier'
                                    then N'Guid'
                                when [types].[name] = N'geography'
                                    then N'Geography'
                                when [types].[name] = N'geometry'
                                    then N'Geometry'
                                else N'String' -- a shot in the dark and hope for the best
                              end,
            [maxLength]     = case -- using types.name to help readability at performance cost
                                when [types].[name] in ( N'nchar', N'nvarchar' )
                                    then case
                                            when [columns].[max_length] = -1
                                                then N'Max'
                                            else CAST(([columns].[max_length] / 2) as nvarchar(10))
                                        end
                                when [types].[name] in ( N'char', N'varchar', N'binary', N'varbinary' )
                                    then case
                                            when [columns].[max_length] = -1
                                                then N'Max'
                                            else CAST([columns].[max_length] as nvarchar(10))
                                        end
                                else null
                              end,
            [isFixedLength] = case
                                when [types].[name] in ( N'nchar', N'char', N'binary', N'timestamp', N'rowversion' )
                                    then N'true'
                                when [types].[name] in ( N'ntext', N'nvarchar', N'text', N'varchar', N'image', N'varbinary', N'xml' )
                                    then N'false'
                                else null
                              end,
            [precision]     = case
                                when [types].[name] = N'float'
                                    -- I could not find any good way to determine the intended precision of a
                                    -- float column, so the best I can do is go by storage space and set the max
                                    -- possible precision for the size.
                                    then case [columns].[max_length]
                                            when 4
                                                then N'24'
                                            else N'53'
                                         end
                                when [types].[name] in ( N'decimal', N'numeric' )
                                    then CAST([columns].[precision] as nvarchar(10))
                                when [types].[name] in ( N'datetime2', N'datetimeoffset' )
                                -- Despite capturing "fractional seconds precision" (https://msdn.microsoft.com/en-us/library/bb630289.aspx), the precision for DATETIME2 and DATETIMEOFFSET is stored in the [scale] column
                                    then CAST([columns].[scale] as nvarchar(10))
                                else null
                              end,
            [scale]         = case
                                when [types].[name] in ( N'decimal', N'numeric' ) 
                                    then CAST([columns].[scale] as nvarchar(10))
                                else null
                              end,
            [isUnicode]     = case
                                when [types].[name] in ( N'char', N'varchar', N'text' )
                                    then N'false'
                                when [types].[name] in ( N'nchar', N'nvarchar', N'ntext', N'xml' )
                                    then N'true'
                                else null
                              end,
            [isNullable]    = case [columns].[is_nullable]
                                when 0
                                    then N'false'
                                when 1
                                    then N'true'
                                else null
                              end,
            [isIdentity]    = case [columns].[is_identity]
                                when 0
                                    then N'false'
                                when 1
                                    then N'true'
                                else null
                              end,
            [isCalculated]  = case [columns].[is_computed]
                               -- TODO: add option reserved column names that should have database-generated values
                                when 0
                                    then N'false'
                                when 1
                                    then N'true'
                                else null
                              end
    from    [sys].[columns]
            inner join
            [sys].[types] on [types].[user_type_id] = [columns].[user_type_id]
    where   [columns].[object_id] = @objectId;
        
    -- Set identity flag for table
    if exists ( select * from @columnInfo where [isIdentity] = N'true' )
    begin;
        set @hasIdentityFlag = 1;
    end;

    -- Populate primary key column info
    if exists ( select 1 from [sys].[indexes] where [object_id] = @objectId and [is_primary_key] = 1 )
    begin;
        update  @columnInfo
        set     [pkIndexId] = [index_columns].[index_column_id]
        from    @columnInfo
                inner join
                [sys].[columns] on [columns].[column_id] = [columnId]
                inner join
                [sys].[index_columns]  on [columns].[object_id] = [index_columns].[object_id] and [columns].[column_id] = [index_columns].[column_id]
                inner join
                [sys].[indexes] on [index_columns].[object_id] = [indexes].[object_id] and [index_columns].[index_id] = [indexes].[index_id]
        where   [columns].[object_id] = @objectId
                and
                [indexes].[is_primary_key] = 1;
    end;

    -- Populate foreign key parent info
    if @isEverFkParent = CAST(1 as bit)
    begin;
        update  @columnInfo
        set     [isFkParent] = CAST(1 as bit)
        from    @columnInfo
                inner join
                [sys].[foreign_key_columns] on [foreign_key_columns].[referenced_column_id] = [columnId]
        where   [foreign_key_columns].[referenced_object_id] = @objectId
                -- We only care if it's a parent column if the child is also in the abstraction
                and exists (    select  *
                                from    @tableListPresented
                                where   [isAddedForFk] is null
                                        and
                                        [objectId] = [foreign_key_columns].[parent_object_id]
                            );
    end;

    -- Populate foreign key child info
    if @isEverFkChild = CAST(1 as bit)
    begin;
        update  @columnInfo
        set     [isFkChild] = CAST(1 as bit)
        from    @columnInfo
                inner join
                [sys].[foreign_key_columns] on [foreign_key_columns].[parent_column_id] = [columnId]
        where   [foreign_key_columns].[parent_object_id] = @objectId;
    end;
    
    -- Populate INSERT proc parameter info
    update  @columnInfo
    set     [isInsertParameter] = CAST(1 as bit)
    where   [isIdentity] = CAST(0 as bit)
            and
            [isCalculated] = CAST(0 as bit)
            and
            [name] not in ( select [name] from @insertParameterExcludedColumns );

    -- Populate UPDATE proc parameter info
    update  @columnInfo
    set     [isUpdateParameter] = CAST(1 as bit)
    where   [isCalculated] = CAST(0 as bit)
            and
            [name] not in ( select [name] from @updateParameterExcludedColumns );

    -- Populate DELETE proc parameter info
    update  @columnInfo
    set     [isDeleteParameter] = CAST(1 as bit)
    where   [pkIndexId] is not null;

    if @debugMode = CAST(1 as bit)
    begin;
        select N'@columnInfo after preparation:';
        select * from @columnInfo;
    end;

--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- ...Write WHERE clause for UPDATE and DELETE
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    if not exists ( select * from @columnInfo where [pkIndexId] is not null )
    begin;
        declare @msg NVARCHAR(MAX);

        set @msg =  N'; select N''No primary key defined for table '
                    + @quotedSchemaQualifiedName
                    + N'. This will probably mess up a lot of stuff.'' as [WARNING_'
                    + @schemaName
                    + N'_'
                    + @objectName
                    + N'];'

        set @crudPresentationStatement = @crudPresentationStatement + @msg;
    end;

    set @targetWhereClause =    N'WHERE'
                                + STUFF(
                                            (    
                                                select      N' AND '
                                                            + QUOTENAME([name], N'[')
                                                            + N' = @'
                                                            + [name]
                                                from        @columnInfo
                                                where       [pkIndexId] is not null
                                                order by    [pkIndexId]
                                                for xml path('')
                                            ) -- end of SELECT
                                            , 1, 4, ''
                                        ); -- end of STUFF
    
    if @debugMode = CAST(1 as bit)
    begin;
        select [targetWhereClause] = @targetWhereClause;
    end;

--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- ...Write target record check for UPDATE and DELETE
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    if @includeTargetRecordCheck = CAST(1 as bit)
    begin;
        set @targetRecordCheck =    @targetRecordCheck
                                    --
                                    + @lineEnd
                                    + N'-- Validate'
                                    + STUFF(
                                               (    
                                                   select      N' and @'
                                                               + [name]
                                                   from        @columnInfo
                                                   where       [pkIndexId] is not null
                                                   order by    [pkIndexId]
                                                   for xml path('')
                                               ) -- end of SELECT
                                               , 1, 4, ''
                                           ) -- end of STUFF
                                    + N' targets a record that exists.'
                                    --
                                    + @lineEnd
                                    + N'IF NOT EXISTS (SELECT * FROM '
                                    + @quotedSchemaQualifiedName
                                    + N' '
                                    + @targetWhereClause
                                    + N')'
                                    --
                                    + @lineEnd
                                    + N'BEGIN;'
                                    --
                                    + @lineEnd
                                    + @tabSpace
                                    -- TODO: Add variable name(s) that violated constraint
                                    + N'THROW 50000, N''Record defined by'
                                    + STUFF(
                                               (    
                                                   select      N' and @'
                                                               + [name]
                                                   from        @columnInfo
                                                   where       [pkIndexId] is not null
                                                   order by    [pkIndexId]
                                                   for xml path('')
                                               ) -- end of SELECT
                                               , 1, 4, ''
                                           ) -- end of STUFF
                                    + N' was not found. No data modified.'', 0;'
                                    --
                                    + @lineEnd
                                    + N'END;';
    end;

    if @debugMode = CAST(1 as bit)
    begin;
        select  [includeTargetRecordCheck]  = @includeTargetRecordCheck,
                [targetRecordCheck]         = @targetRecordCheck;
    end;

--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- ...Handle all foreign key related material
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
-- Because we have to step through each foreign key and its child columns to construct our statements correctly,
-- we want to handle everything related to the foreign keys at once. This includes:
-- 1. Key validation checks for the INSERT and UPDATE procs
-- 2. SSDL Association
-- 3. SSDL AssociationSet
-- 4. CSDL Association
-- 5. CSDL AssociationSet

    if CAST(1 as bit) in ( @isEverFkParent, @isEverFkChild )
    begin;
        delete @foreignKeyInfo;

        insert @foreignKeyInfo (
            [foreignKeyName],
            [foreignKeyObjectId],
            [isCurrentTableParent],
            [parentObjectId],
            [parentName],
            [parentQuotedSchemaQualifiedName],
            [childObjectId],
            [childName],
            [childQuotedSchemaQualifiedName],
            [fkColumnId],
            [parentColumnName],
            [childColumnName]
            )
        select  [foreignKeyName]                    =   OBJECT_NAME([foreign_key_columns].[constraint_object_id]),
                [foreignKeyObjectId]                =   [foreign_key_columns].[constraint_object_id],
                [isCurrentTableParent]              =   case
                                                          when [foreign_key_columns].[referenced_object_id] = @objectId
                                                              then CAST(1 as bit)
                                                          else CAST(0 as bit)
                                                        end,
                [parentObjectId]                    =   [foreign_key_columns].[referenced_object_id],
                [parentName]                        =   OBJECT_NAME([foreign_key_columns].[referenced_object_id]),
                [parentQuotedSchemaQualifiedName]   =   QUOTENAME(OBJECT_SCHEMA_NAME([foreign_key_columns].[referenced_object_id]), N'[')
                                                        + N'.'
                                                        + QUOTENAME(OBJECT_NAME([foreign_key_columns].[referenced_object_id]), N'['),
                [childObjectId]                     =   [foreign_key_columns].[parent_object_id],
                [childName]                         =   OBJECT_NAME([foreign_key_columns].[parent_object_id]),
                [childQuotedSchemaQualifiedName]    =   QUOTENAME(OBJECT_SCHEMA_NAME([foreign_key_columns].[parent_object_id]), N'[')
                                                        + N'.'
                                                        + QUOTENAME(OBJECT_NAME([foreign_key_columns].[parent_object_id]), N'['),
                [fkColumnId]                        =   [foreign_key_columns].[constraint_column_id],
                [parentColumnName]                  =   parent.[name], -- we don't quote this because we'll want it raw for the Associations
                [childColumnName]                   =   child.[name] -- we don't quote this because we'll want it raw for the Associations
        from    [sys].[foreign_key_columns]
                inner join
                [sys].[columns] as parent on parent.[object_id] = [foreign_key_columns].[referenced_object_id] and parent.[column_id] = [foreign_key_columns].[referenced_column_id]
                inner join
                [sys].[columns] as child on child.[object_id] = [foreign_key_columns].[parent_object_id] and child.[column_id] = [foreign_key_columns].[parent_column_id]
        where   [foreign_key_columns].[parent_object_id] = @objectId
                or
                [foreign_key_columns].[referenced_object_id] = @objectId;

        declare [fkCursor] cursor
        for select distinct [foreignKeyName],
                            [foreignKeyObjectId],
                            [isCurrentTableParent],
                            [parentObjectId],
                            [parentName],
                            [parentQuotedSchemaQualifiedName],
                            [childObjectId],
                            [childName],
                            [childQuotedSchemaQualifiedName]
            from            @foreignKeyInfo
            order by        [foreignKeyObjectId];

        open [fkCursor];

        fetch next from [fkCursor]
        into @fkName, @fkObjectId, @isCurrentTableParent, @fkParentObjectId, @fkParentName, @fkParentQuotedSchemaQualifiedName, @fkChildObjectId, @fkChildName, @fkChildQuotedSchemaQualifiedName;

        while @@FETCH_STATUS = 0
        begin;
            -- If the current table is not the parent of the current FK, create validation checks for the INSERT
            -- and UPDATE procs.
            if  @isCurrentTableParent = CAST(0 as bit)
                and
                @includeKeyValidationCheck = CAST(1 as bit)
            begin;
                set @thisKeyValidationCheckWhereClause =    N'WHERE'
                                                            + STUFF(
                                                                        (    
                                                                            select      N' AND '
                                                                                        + QUOTENAME([parentColumnName], N'[')
                                                                                        + N' = @'
                                                                                        + [childColumnName]
                                                                            from        @foreignKeyInfo
                                                                            where       [foreignKeyObjectId] = @fkObjectId
                                                                            order by    [fkColumnId]
                                                                            for xml path('')
                                                                        ) -- end of SELECT
                                                                        , 1, 4, ''
                                                                    ); -- end of STUFF

                set @keyValidationCheck =   @keyValidationCheck
                                            --
                                            + @lineEnd
                                            + N'-- Validate'
                                            + STUFF(
                                                       (    
                                                           select      N' and @'
                                                                       + [childColumnName]
                                                           from        @foreignKeyInfo
                                                           where       [foreignKeyObjectId] = @fkObjectId
                                                           order by    [fkColumnId]
                                                           for xml path('')
                                                       ) -- end of SELECT
                                                       , 1, 4, ''
                                                   ) -- end of STUFF
                                            --
                                            + @lineEnd
                                            + N'IF NOT EXISTS (SELECT * FROM '
                                            + @fkParentQuotedSchemaQualifiedName
                                            + N' '
                                            + @thisKeyValidationCheckWhereClause
                                            + N')'
                                            --
                                            + @lineEnd
                                            + N'BEGIN;'
                                            --
                                            + @lineEnd
                                            + @tabSpace
                                            -- TODO: Add variable name(s) that violated constraint
                                            + N'THROW 50000, N''Submitted value for'
                                            + STUFF(
                                                       (    
                                                           select      N' or @'
                                                                       + [childColumnName]
                                                           from        @foreignKeyInfo
                                                           where       [foreignKeyObjectId] = @fkObjectId
                                                           order by    [fkColumnId]
                                                           for xml path('')
                                                       ) -- end of SELECT
                                                       , 1, 3, ''
                                                   ) -- end of STUFF
                                            + N' was not found in referenced table and would create an orphan. No data modified.'', 0;'
                                            --
                                            + @lineEnd
                                            + N'END;'
                                            --
                                            + @lineEnd; -- We have to add the extra line here to insure proper spacing of multiple keys
            end; -- end key validation checks
            -- Otherwise, if the current table is the parent of the current FK, create the required Association elements
            else begin;
                if  @isCurrentTableParent = CAST(1 as bit)
                    and
                    @includeKeyValidationCheck = CAST(1 as bit)
                    and
                    -- We only want delete key validation checks for tables exposed to write operations in the DAL
                    @isReadOnly = CAST(0 as bit)
                begin;
                    set @deleteKeyValidationCheck = @deleteKeyValidationCheck
                                                    --
                                                    + @lineEnd
                                                    + N'-- Validate no orphans created in '
                                                    + @fkChildName
                                                    --
                                                    + @lineEnd
                                                    + N'IF EXISTS (SELECT * FROM '
                                                    + @fkChildQuotedSchemaQualifiedName
                                                    + N' WHERE'
                                                    + STUFF(
                                                        (    
                                                            select      N' AND '
                                                                        + QUOTENAME([childColumnName], N'[')
                                                                        + N' = (SELECT '
                                                                        + QUOTENAME([parentColumnName], N'[')
                                                                        + N' FROM '
                                                                        + @fkParentQuotedSchemaQualifiedName
                                                                        + N' '
                                                                        + @targetWhereClause
                                                                        + N')'
                                                            from        @foreignKeyInfo
                                                            where       [foreignKeyObjectId] = @fkObjectId
                                                            order by    [fkColumnId]
                                                            for xml path('')
                                                        ) -- end of SELECT
                                                        , 1, 4, ''
                                                    )
                                                    + N')'
                                                    --
                                                    + @lineEnd
                                                    + N'BEGIN;'
                                                    --
                                                    + @lineEnd
                                                    + @tabSpace
                                                    -- TODO: Add variable name(s) that violated constraint
                                                    + N'THROW 50000, N''Target record has at least one child '
                                                    + @fkChildName
                                                    + N', so deleting would create an orphan. No data modified.'', 0;'
                                                    --
                                                    + @lineEnd
                                                    + N'END;'
                                                    --
                                                    + @lineEnd; -- We have to add the extra line here to insure proper spacing of multiple keys
                end;

                set @thisCsdlAssociation =  N'<Association Name="'
                                            + @fkName
                                            + N'">'
                                            --
                                            + @lineEnd
                                            + @tab
                                            + N'<End Role="'
                                            + @fkParentName
                                            + N'" Type="Self.'
                                            + @fkParentName
                                            + N'" Multiplicity="1"'
                                            + @xmlElementClose
                                            --
                                            + @lineEnd
                                            + @tab
                                            + N'<End Role="'
                                            + @fkChildName
                                            + N'" Type="Self.'
                                            + @fkChildName
                                            + N'" Multiplicity="*"'
                                            + @xmlElementClose
                                            --
                                            + @lineEnd
                                            + @tab
                                            + N'<ReferentialConstraint>'
                                            --
                                            + @lineEnd
                                            + REPLICATE(@tab, 2)
                                            + N'<Principal Role="'
                                            + @fkParentName
                                            + + N'">'
                                            --
                                            + REPLACE(REPLACE(REPLACE(
                                                                (    
                                                                    select      @lineEnd
                                                                                + REPLICATE(@tab, 3)
                                                                                + '<PropertyRef Name="'
                                                                                + [parentColumnName]
                                                                                + N'"'
                                                                                + @xmlElementClose
                                                                    from        @foreignKeyInfo
                                                                    where       [foreignKeyObjectId] = @fkObjectId
                                                                    order by    [fkColumnId]
                                                                    for xml path('')
                                                                ) -- end of SELECT
                                                                , N'&#x0D;', NCHAR(13)
                                                            ) -- end of REPLACE carriage return
                                                        , N'&lt;', N'<'
                                                        ) -- end of REPLACE less than
                                                    -- Because we are dealing with sub-elements, we know every closing bracket closes an element
                                                    , N'&gt;', N'>'
                                                    ) -- end of REPLACE greater than
                                            --
                                            + @lineEnd
                                            + REPLICATE(@tab, 2)
                                            + N'</Principal>'
                                            --
                                            + @lineEnd
                                            + REPLICATE(@tab, 2)
                                            + N'<Dependent Role="'
                                            + @fkChildName
                                            + + N'">'
                                            --
                                            + REPLACE(REPLACE(REPLACE(
                                                                (    
                                                                    select      @lineEnd
                                                                                + REPLICATE(@tab, 3)
                                                                                + '<PropertyRef Name="'
                                                                                + [childColumnName]
                                                                                + N'"'
                                                                                + @xmlElementClose
                                                                    from        @foreignKeyInfo
                                                                    where       [foreignKeyObjectId] = @fkObjectId
                                                                    order by    [fkColumnId]
                                                                    for xml path(N'')
                                                                ) -- end of SELECT
                                                                , N'&#x0D;', NCHAR(13)
                                                            ) -- end of REPLACE carriage return
                                                        , N'&lt;', N'<'
                                                        ) -- end of REPLACE less than
                                                    -- Because we are dealing with sub-elements, we know every closing bracket closes an element
                                                    , N'&gt;', N'>'
                                                    ) -- end of REPLACE greater than
                                            --
                                            + @lineEnd
                                            + REPLICATE(@tab, 2)
                                            + N'</Dependent>'
                                            --
                                            + @lineEnd
                                            + @tab
                                            + N'</ReferentialConstraint>'
                                            --
                                            + @lineEnd
                                            + N'</Association>'
                                            --
                                            + @lineEnd;
                
                -- add @thisCsdlAssociation to the complete set
                set @csdlAssociations   =   @csdlAssociations
                                            + @thisCsdlAssociation;

                set @thisCsdlAssociationSet =   N'<AssociationSet Name="'
                                                + @fkName
                                                + N'" Association="Self.'
                                                + @fkName
                                                + N'">'
                                                --
                                                + @lineEnd
                                                + @tab
                                                + N'<End Role="'
                                                + @fkParentName
                                                + N'" EntitySet="'
                                                + @fkParentName
                                                + N's"'
                                                + @xmlElementClose
                                                --
                                                + @lineEnd
                                                + @tab
                                                + N'<End Role="'
                                                + @fkChildName
                                                + N'" EntitySet="'
                                                + @fkChildName
                                                + N's"'
                                                + @xmlElementClose
                                                --
                                                + @lineEnd
                                                + N'</AssociationSet>'
                                                --
                                                + @lineEnd;
                
                -- add @thisCsdlAssociationSet to the complete set
                set @csdlAssociationSets    =   @csdlAssociationSets
                                                + @thisCsdlAssociationSet;
            end; -- end Association and AssociationSet element generation
            
            -- Create NavigationProperty elements for the table if both tables are in the list
            if  exists ( select * from @tableListPresented where [objectId] = @fkParentObjectId )
                and
                exists ( select * from @tableListPresented where [objectId] = @fkChildObjectId )
            begin;
                set @thisCsdlNavigationProperties = @thisCsdlNavigationProperties
                                                    + @lineEnd
                                                    + N'<NavigationProperty Name="'
                                                    + case
                                                        when @objectId = @fkParentObjectId
                                                            then @fkChildName
                                                        else @fkParentName
                                                      end
                                                    + N'" Relationship="Self.'
                                                    + @fkName
                                                    + N'" FromRole="'
                                                    + case
                                                        when @objectId = @fkParentObjectId
                                                            then @fkParentName
                                                        else @fkChildName
                                                      end
                                                    + N'" ToRole="'
                                                    + case
                                                        when @objectId = @fkParentObjectId
                                                            then @fkChildName
                                                        else @fkParentName
                                                      end
                                                    + N'"'
                                                    + @xmlElementClose;
            end;
                    
            fetch next from [fkCursor]
            into @fkName, @fkObjectId, @isCurrentTableParent, @fkParentObjectId, @fkParentName, @fkParentQuotedSchemaQualifiedName, @fkChildObjectId, @fkChildName, @fkChildQuotedSchemaQualifiedName;
        end; -- end fkCursor WHILE loop

        close [fkCursor];
        deallocate [fkCursor];
    end; -- end foreign key processing
    
    if @debugMode = CAST(1 as bit)
    begin;
        select  [includeKeyValidationCheck] = @includeKeyValidationCheck,
                [keyValidationCheck]        = @keyValidationCheck,
                [ssdlAssociations]          = @thisSsdlAssociation,
                [ssdlAssociationSets]       = @thisSsdlAssociationSet,
                [csdlAssociations]          = @thisCsdlAssociation,
                [csdlAssociationSets]       = @thisCsdlAssociationSet,
                [csdlNavigationProperties]  = @thisCsdlNavigationProperties;
    end;

--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- ...Write covering view
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    -- Begin standard script header
    set @coveringView = N'--============================================================================'
                        --
                        + @lineEnd
                        + N'-- '
                        + @quotedSchemaQualifiedName
                        + N' covering view for use by the DAL.'
                        --
                        + @lineEnd
                        + N'--============================================================================'
    -- CREATE VIEW start
                        --
                        + @lineEnd
                        + N'CREATE VIEW '
                        + QUOTENAME(@databaseAbstractionSchema, N'[')
                        + N'.'
                        + QUOTENAME(@coveringViewName, N'[')
                        + N' AS'
                        --
                        + @lineEnd
                        + N'SELECT'
    -- Add column list
                        + STUFF(REPLACE(STUFF(
                                            (
                                                select      @lineEnd -- This becomes 7 characters in XML because NCHAR(13) becomes '&#x0D;'
                                                            + @tabSpace
                                                            + N', '
                                                            + QUOTENAME([name], N'[')
                                                from        @columnInfo
                                                order by    [columnId]
                                                for xml path('')
                                            ) -- end of SELECT
                                            , 1, 11, N''
                                        ) -- end of inner STUFF
                                        , N'&#x0D;', NCHAR(13)
                                    ) -- end of REPLACE carriage return
                                    , 1, LEN(@tabSpace) + LEN(@lineEnd), @lineEnd + @tabSpace
                                ) -- end of outer STUFF
    -- Add FROM clause
                        --
                        + @lineEnd
                        + N'FROM '
                        + @quotedSchemaQualifiedName
                        + N';'
                        --
                        + @lineEnd;

    -- present covering view
    set @crudPresentationStatement =    @crudPresentationStatement
                                        + @coveringView
                                        + @lineEnd
                                        + N'GO';

--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- ...Write INSERT proc
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    -- We only want to write CUD objects for objects exposed to write operations. The variable initialization
    -- after fetching the next record from the table cursor will set all of the values usually populated in this
    -- section to empty strings, so it won't affect concatenation operations later.
    if @isReadOnly = CAST(0 as bit)
    begin;
        -- Begin standard script header
        set @createProc =   N'--============================================================================'
                            --
                            + @lineEnd
                            + N'-- '
                            + @quotedSchemaQualifiedName
                            + N' create procedure for use by the DAL.'
                            --
                            --
                            + @lineEnd
                            + N'--============================================================================'
        -- CREATE PROC start
                            --
                            + @lineEnd
                            + N'CREATE PROC '
                            + QUOTENAME(@databaseAbstractionSchema, N'[')
                            + N'.'
                            + QUOTENAME(@insertProcName, N'[')
        -- Add parameter list
                            --
                            + STUFF(REPLACE(STUFF(
                                                (    
                                                    select      @lineEnd
                                                                + @tabSpace
                                                                + ', @'
                                                                + [name]
                                                                + @tabSpace
                                                                + [dbType]
                                                                + case -- using types.name to help readability at performance cost
                                                                    when [dbType] in ( N'nchar', N'nvarchar', N'char', N'varchar', N'binary', N'varbinary' )
                                                                        then N'(' + [maxLength] + N')'
                                                                    when [dbType] in ( N'decimal', N'numeric' )
                                                                        then N'(' + [precision] + N', ' + [scale] + N')'
                                                                    when [dbType] in ( N'float', N'datetime2', N'datetimeoffset' )
                                                                        then N'(' + [precision] + N')'
                                                                    else ''
                                                                  end
                                                    from        @columnInfo
                                                    where       [isInsertParameter] = CAST(1 as bit)
                                                    order by    [columnId]
                                                    for xml path('')
                                                ) -- end of SELECT
                                                , 1, 12, ''
                                            ) -- end of inner STUFF
                                            , N'&#x0D;', NCHAR(13)
                                        ) -- end of REPLACE carriage return
                                        , 1, 1, @lineEnd + @tabSpace
                                    ) -- end of outer STUFF
        -- CREATE PROC end, INSERT beginning
                            --
                            + @lineEnd
                            + N'AS'
                            --
                            + @lineEnd
                            + N'BEGIN'
                            --
                            + @lineEnd
                            + @tabSpace
                            + N'SET NOCOUNT ON;'
        -- add key validation check
                            --
                            + @lineEnd
                            -- We replace each line end with a line end plus a tab to nest the code properly
                            + REPLACE(@keyValidationCheck, @lineEnd, @lineEnd + @tabSpace)
                            --
                            + @lineEnd
                            + @tabSpace
                            + N'INSERT '
                            + @quotedSchemaQualifiedName
                            + N' ('
        -- add INSERT list
                            + STUFF(
                                    (    
                                        select      ', ' + 
                                                    QUOTENAME([name],'[')
                                        from        @columnInfo
                                        where       isInsertParameter = CAST(1 as bit)
                                        order by    [columnId]
                                        for xml path('')
                                    ) -- end of SELECT
                                    , 1, 2, ''
                                ) -- end of STUFF
        -- INSERT ending, SELECT begin
                            + N')'
                            --
                            + @lineEnd
                            + @tabSpace
                            + N'SELECT'
                            
        -- add SELECT values
                            --
                            + STUFF(REPLACE(STUFF(
                                            (    
                                                select      @lineEnd 
                                                            + REPLICATE(@tabSpace, 2)
                                                            + ', '
                                                            + QUOTENAME([name], '[')
                                                            + N' = CASE'
                                                            + @lineEnd
                                                            + REPLICATE(@tabSpace, 4)
                                                            + N'WHEN 1=1'
                                                            + @lineEnd
                                                            + REPLICATE(@tabSpace, 5)
                                                            + N'THEN @'
                                                            + [name]
                                                            + @lineEnd
                                                            + REPLICATE(@tabSpace, 4)
                                                            + N'ELSE @'
                                                            + [name]
                                                            + @lineEnd
                                                            + REPLICATE(@tabSpace, 3)
                                                            + N'END'
                                                from        @columnInfo
                                                where       isInsertParameter = CAST(1 as bit)
                                                order by    [columnId]
                                                for xml path('')
                                            ) -- end of SELECT
                                            , 1, 15, N''
                                        ) -- end of inner STUFF
                                        , N'&#x0D;', NCHAR(13)
                                    ) -- end of REPLACE carriage return
                                    , 1, 1, @lineEnd + REPLICATE(@tabSpace, 2)
                                ) -- end of outer STUFF
                            --
                            + @lineEnd
                            + REPLICATE(@tabSpace, 2)
                            + N';'
        -- If they exist, return any values not submitted as parameters
                            --
                            + case
                                when    @hasIdentityFlag = 1
                                        and
                                        1 = ( select count(1) from @columnInfo where [isInsertParameter] is null )
                                    then    @lineEnd
                                            --
                                            + @lineEnd
                                            + @tabSpace
                                            + N'-- Return identity value for consumption by Entity Framework'
                                            --
                                            + @lineEnd
                                            + @tabSpace
                                            + N'SELECT '
                                            + ( -- A table may only have one identity column (see https://msdn.microsoft.com/en-us/library/ms186775.aspx)
                                                select     QUOTENAME([name], N'[')
                                                from        @columnInfo
                                                where       [isIdentity] = N'true'
                                            ) -- end of SELECT
                                            + N' = SCOPE_IDENTITY();'
                                when    @hasIdentityFlag = 1
                                        and
                                        1 < ( select count(1) from @columnInfo where [isInsertParameter] is null )
                                    then    @lineEnd
                                            --
                                            + @lineEnd
                                            + @tabSpace
                                            + N'-- Return column values not submitted as parameters for consumption by Entity Framework'
                                            --
                                            + @lineEnd
                                            + @tabSpace
                                            + N'DECLARE @'
                                            + ( -- A table may only have one identity column (see https://msdn.microsoft.com/en-us/library/ms186775.aspx)
                                                select     [name]
                                                            + @tabSpace
                                                            + [dbType]
                                                            + case -- using types.name to help readability at performance cost
                                                                when [dbType] in ( N'nchar', N'nvarchar', N'char', N'varchar', N'binary', N'varbinary' )
                                                                    then N'(' + [maxLength] + N')'
                                                                when [dbType] in ( N'decimal', N'numeric' )
                                                                    then N'(' + [precision] + N', ' + [scale] + N')'
                                                                when [dbType] in ( N'float', N'datetime2', N'datetimeoffset' )
                                                                    then N'(' + [precision] + N')'
                                                                else ''
                                                              end
                                                from        @columnInfo
                                                where       [isIdentity] = N'true'
                                            ) -- end of SELECT
                                            + N' = SCOPE_IDENTITY();'
                                            --
                                            + @lineEnd
                                            --
                                            + @lineEnd
                                            + @tabSpace
                                            + N'SELECT'
                                            --
                                            + STUFF(REPLACE(STUFF(
                                                            (    
                                                                select      @lineEnd
                                                                            + REPLICATE(@tabSpace, 3)
                                                                            + ', '
                                                                            + QUOTENAME([name], N'[')
                                                                from        @columnInfo
                                                                where       [isInsertParameter] is null
                                                                order by    [columnId]
                                                                for xml path('')
                                                            ) -- end of SELECT
                                                            , 1, 20, ''
                                                        ) -- end of inner STUFF
                                                        , N'&#x0D;', NCHAR(13)
                                                    ) -- end of REPLACE carriage return
                                                    , 1, 1, N'  '
                                                ) -- end of outer STUFF
                                            --
                                            + @lineEnd
                                            + @tabSpace
                                            + N'FROM '
                                            + QUOTENAME(@schemaName, N'[')
                                            + N'.'
                                            + QUOTENAME(@objectName, N'[')
                                            --
                                            + @lineEnd
                                            + @tabSpace
                                            + @targetWhereClause
                                            + N';'
                                when    @hasIdentityFlag <> 1
                                        and
                                        exists ( select * from @columnInfo where [isInsertParameter] is null )
                                    then    @lineEnd
                                            --
                                            + @lineEnd
                                            + @tabSpace
                                            + N'-- Return column values not submitted as parameters for consumption by Entity Framework'
                                            --
                                            + @lineEnd
                                            + @tabSpace
                                            + N'SELECT'
                                            --
                                            + STUFF(REPLACE(STUFF(
                                                            (    
                                                                select      @lineEnd
                                                                            + REPLICATE(@tabSpace, 3)
                                                                            + ', '
                                                                            + QUOTENAME([name], N'[')
                                                                from        @columnInfo
                                                                where       [isInsertParameter] is null
                                                                order by    [columnId]
                                                                for xml path('')
                                                            ) -- end of SELECT
                                                            , 1, 20, ''
                                                        ) -- end of inner STUFF
                                                        , N'&#x0D;', NCHAR(13)
                                                    ) -- end of REPLACE carriage return
                                                    , 1, 1, N'  '
                                                ) -- end of outer STUFF
                                            --
                                            + @lineEnd
                                            + @tabSpace
                                            + N'FROM '
                                            + QUOTENAME(@schemaName, N'[')
                                            + N'.'
                                            + QUOTENAME(@objectName, N'[')
                                            --
                                            + @lineEnd
                                            + @tabSpace
                                            + @targetWhereClause
                                            + N';'
                                else N''
                              end
                            --
                            + @lineEnd
                            + N'END;'
                            --
                            + @lineEnd;

        -- present create proc
        set @crudPresentationStatement =    @crudPresentationStatement
                                            + @lineEnd
                                            + @createProc
                                            + @lineEnd
                                            + N'GO';

        --------------------------------------------------------------------------------------------------------------
        -- write SSDL function for create proc
        --------------------------------------------------------------------------------------------------------------
        set @thisSsdlFunction = N'<Function Name="'
                                + @insertProcName
                                + N'" Aggregate="false" BuiltIn="false" NiladicFunction="false" IsComposable="false" ParameterTypeSemantics="AllowImplicitConversion" Schema="'
                                + @databaseAbstractionSchema
                                + N'">'
                                + @lineEnd
                                --
                                + REPLACE(REPLACE(REPLACE(
                                                    (    
                                                        select      @tab
                                                                    + '<Parameter Name="'
                                                                    + [name]
                                                                    + N'" Type="'
                                                                    + [dbType]
                                                                    + N'" Mode="In"'
                                                                    + case -- using types.name to help readability at performance cost
                                                                        when [dbType] in ( N'nchar', N'nvarchar', N'char', N'varchar', N'binary', N'varbinary' )
                                                                            then N' MaxLength="' + [maxLength] + N'"'
                                                                        when [dbType] in ( N'decimal', N'numeric' )
                                                                            then N' Precision="' + [precision] + N'" Scale="' + [scale] + N'"'
                                                                        when [dbType] in ( N'float', N'datetime2', N'datetimeoffset' )
                                                                            then N' Precision="' + [precision] + N'"'
                                                                        else ''
                                                                      end
                                                                    + @xmlElementClose
                                                                    + @lineEnd
                                                        from        @columnInfo
                                                        where       [isInsertParameter] = CAST(1 as bit)
                                                        order by    [columnId]
                                                        for xml path('')
                                                    ) -- end of SELECT
                                                    , N'&#x0D;', NCHAR(13)
                                                ) -- end of REPLACE carriage return
                                                , N'&lt;', N'<'
                                            ) -- end of REPLACE less than
                                            , N'&gt;', N'>'
                                        ) -- end of REPLACE greater than
                                --
                                + N'</Function>'
                                + @lineEnd;

        -- add create function to SSDL functions
        set @ssdlFunctions  =   @ssdlFunctions
                                + @thisSsdlFunction;

--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- ...Write UPDATE proc
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
        -- Begin standard script header
        set @updateProc =   N'--============================================================================'
                            --
                            + @lineEnd
                            + N'-- '
                            + @quotedSchemaQualifiedName
                            + N' update procedure for use by the DAL.'
                            --
                            + @lineEnd
                            + N'--============================================================================'
        -- CREATE PROC start
                            --
                            + @lineEnd
                            + N'CREATE PROC '
                            + QUOTENAME(@databaseAbstractionSchema, N'[')
                            + N'.'
                            + QUOTENAME(@updateProcName, N'[')
        -- Add parameter list
                            --
                            + STUFF(REPLACE(STUFF(
                                                (    
                                                    select      @lineEnd
                                                                + @tabSpace
                                                                + ', @'
                                                                + [name]
                                                                + @tabSpace
                                                                + [dbType]
                                                                + case -- using types.name to help readability at performance cost
                                                                    when [dbType] in ( N'nchar', N'nvarchar', N'char', N'varchar', N'binary', N'varbinary' )
                                                                        then N'(' + [maxLength] + N')'
                                                                    when [dbType] in ( N'decimal', N'numeric' )
                                                                        then N'(' + [precision] + N', ' + [scale] + N')'
                                                                    when [dbType] in ( N'float', N'datetime2', N'datetimeoffset' )
                                                                        then N'(' + [precision] + N')'
                                                                    else ''
                                                                  end
                                                    from        @columnInfo
                                                    where       [isUpdateParameter] = CAST(1 as bit)
                                                    order by    [columnId]
                                                    for xml path('')
                                                ) -- end of SELECT
                                                , 1, 12, ''
                                            ) -- end of inner STUFF
                                            , N'&#x0D;', NCHAR(13)
                                        ) -- end of REPLACE carriage return
                                        , 1, 1, @lineEnd + @tabSpace
                                    ) -- end of outer STUFF
        -- CREATE PROC end, UPDATE beginning
                            --
                            + @lineEnd
                            + N'AS'
                            --
                            + @lineEnd
                            + N'BEGIN'
                            --
                            + @lineEnd
                            + @tabSpace
                            + N'SET NOCOUNT ON;'
        -- add target record check
                            --
                            + @lineEnd
                            -- We replace each line end with a line end plus a tab to nest the code properly
                            + REPLACE(@targetRecordCheck, @lineEnd, @lineEnd + @tabSpace)
        -- add key validation check
                            --
                            + @lineEnd
                            + @tabSpace
                            -- We replace each line end with a line end plus a tab to nest the code properly
                            + REPLACE(@keyValidationCheck, @lineEnd, @lineEnd + @tabSpace)
                            --
                            + @lineEnd
                            + @tabSpace
                            + N'UPDATE '
                            + @quotedSchemaQualifiedName
                            --
                            + @lineEnd
                            + @tabSpace
                            + N'SET'
        -- add UPDATEs
                            --
                            + STUFF(REPLACE(STUFF(
                                            (    
                                                select      @lineEnd 
                                                            + REPLICATE(@tabSpace, 2)
                                                            + ', '
                                                            + QUOTENAME([name], '[')
                                                            + N' = CASE'
                                                            + @lineEnd
                                                            + REPLICATE(@tabSpace, 4)
                                                            + N'WHEN 1=1'
                                                            + @lineEnd
                                                            + REPLICATE(@tabSpace, 5)
                                                            + N'THEN @'
                                                            + [name]
                                                            + @lineEnd
                                                            + REPLICATE(@tabSpace, 4)
                                                            + N'ELSE @'
                                                            + [name]
                                                            + @lineEnd
                                                            + REPLICATE(@tabSpace, 3)
                                                            + N'END'
                                                from        @columnInfo
                                                where       [isUpdateParameter] = CAST(1 as bit)
                                                order by    [columnId]
                                                for xml path('')
                                            ) -- end of SELECT
                                            , 1, 16, ''
                                        ) -- end of inner STUFF
                                        , N'&#x0D;', NCHAR(13)
                                    ) -- end of REPLACE
                                    , 1, 1, @lineEnd + REPLICATE(@tabSpace, 2)
                                ) -- end of outer STUFF
        -- Add WHERE clause
                            --
                            + @lineEnd
                            + @tabSpace
                            + @targetWhereClause
                            + N';'
        -- If they exist, return any values not submitted as parameters
                            --
                            + case
                                when exists ( select * from @columnInfo where [isUpdateParameter] is null )
                                    then    @lineEnd
                                            --
                                            + @lineEnd
                                            + @tabSpace
                                            + N'-- Return column values not submitted as parameters for consumption by Entity Framework'
                                            --
                                            + @lineEnd
                                            + @tabSpace
                                            + N'SELECT'
                                            --
                                            + STUFF(REPLACE(STUFF(
                                                            (    
                                                                select      @lineEnd
                                                                            + REPLICATE(@tabSpace, 3)
                                                                            + ', '
                                                                            + QUOTENAME([name], N'[')
                                                                from        @columnInfo
                                                                where       [isUpdateParameter] is null
                                                                order by    [columnId]
                                                                for xml path('')
                                                            ) -- end of SELECT
                                                            , 1, 20, ''
                                                        ) -- end of inner STUFF
                                                        , N'&#x0D;', NCHAR(13)
                                                    ) -- end of REPLACE carriage return
                                                    , 1, 1, N'  '
                                                ) -- end of outer STUFF
                                            --
                                            + @lineEnd
                                            + @tabSpace
                                            + N'FROM '
                                            + QUOTENAME(@schemaName, N'[')
                                            + N'.'
                                            + QUOTENAME(@objectName, N'[')
                                            --
                                            + @lineEnd
                                            + @tabSpace
                                            + @targetWhereClause
                                            + N';'
                                else N''
                              end
        -- Close out proc
                            --
                            + @lineEnd
                            + N'END;'
                            --
                            + @lineEnd;

        -- present update proc
        set @crudPresentationStatement =    @crudPresentationStatement
                                            + @lineEnd
                                            + @updateProc
                                            + @lineEnd
                                            + N'GO'
                                            + @lineEnd;

        --------------------------------------------------------------------------------------------------------------
        -- write SSDL function for update proc
        --------------------------------------------------------------------------------------------------------------
        set @thisSsdlFunction = N'<Function Name="'
                                + @updateProcName
                                + N'" Aggregate="false" BuiltIn="false" NiladicFunction="false" IsComposable="false" ParameterTypeSemantics="AllowImplicitConversion" Schema="'
                                + @databaseAbstractionSchema
                                + N'">'
                                + @lineEnd
                                --
                                + REPLACE(REPLACE(REPLACE(
                                                    (    
                                                        select      @tab
                                                                    + '<Parameter Name="'
                                                                    + [name]
                                                                    + N'" Type="'
                                                                    + [dbType]
                                                                    + N'" Mode="In"'
                                                                    + case -- using types.name to help readability at performance cost
                                                                        when [dbType] in ( N'nchar', N'nvarchar', N'char', N'varchar', N'binary', N'varbinary' )
                                                                            then N' MaxLength="' + [maxLength] + N'"'
                                                                        when [dbType] in ( N'decimal', N'numeric' )
                                                                            then N' Precision="' + [precision] + N'" Scale="' + [scale] + N'"'
                                                                        when [dbType] in ( N'float', N'datetime2', N'datetimeoffset' )
                                                                            then N' Precision="' + [precision] + N'"'
                                                                        else ''
                                                                      end
                                                                    + @xmlElementClose
                                                                    + @lineEnd
                                                        from        @columnInfo
                                                        where       [isUpdateParameter] = CAST(1 as bit)
                                                        order by    [columnId]
                                                        for xml path('')
                                                    ) -- end of SELECT
                                                    , N'&#x0D;', NCHAR(13)
                                                ) -- end of REPLACE carriage return
                                                , N'&lt;', N'<'
                                            ) -- end of REPLACE less than
                                            , N'&gt;', N'>'
                                        ) -- end of REPLACE greater than
                                --
                                + N'</Function>'
                                + @lineEnd;

        -- add update function to SSDL functions
        set @ssdlFunctions  =   @ssdlFunctions
                                + @thisSsdlFunction;

--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- ...Write DELETE proc
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
        -- Begin standard script header
        set @deleteProc =   N'--============================================================================'
                            --
                            + @lineEnd
                            + N'-- '
                            + @quotedSchemaQualifiedName
                            + N' update procedure for use by the DAL.'
                            --
                            + @lineEnd
                            + N'--============================================================================'
        -- CREATE PROC start
                            --
                            + @lineEnd
                            + N'CREATE PROC '
                            + QUOTENAME(@databaseAbstractionSchema, N'[')
                            + N'.'
                            + QUOTENAME(@deleteProcName, N'[')
        -- Add parameter list
                            --
                            + STUFF(REPLACE(STUFF(
                                                (    
                                                    select      @lineEnd
                                                                + @tabSpace
                                                                + ', @'
                                                                + [name]
                                                                + @tabSpace
                                                                + [dbType]
                                                                + case -- using types.name to help readability at performance cost
                                                                    when [dbType] in ( N'nchar', N'nvarchar', N'char', N'varchar', N'binary', N'varbinary' )
                                                                        then N'(' + [maxLength] + N')'
                                                                    when [dbType] in ( N'decimal', N'numeric' )
                                                                        then N'(' + [precision] + N', ' + [scale] + N')'
                                                                    when [dbType] in ( N'float', N'datetime2', N'datetimeoffset' )
                                                                        then N'(' + [precision] + N')'
                                                                    else ''
                                                                  end
                                                    from        @columnInfo
                                                    where       [isDeleteParameter] = CAST(1 as bit)
                                                    order by    [pkIndexId]
                                                    for xml path('')
                                                ) -- end of SELECT
                                                , 1, 12, ''
                                            ) -- end of inner STUFF
                                            , N'&#x0D;', NCHAR(13)
                                        ) -- end of REPLACE carriage return
                                        , 1, 1, @lineEnd + @tabSpace
                                    ) -- end of outer STUFF
        -- CREATE PROC end, DELETE beginning
                            --
                            + @lineEnd
                            + N'AS'
                            + @lineEnd
                            + N'BEGIN'
                            + @lineEnd
                            + @tabSpace
                            + N'SET NOCOUNT ON;'
        -- add target record check
                            --
                            + @lineEnd
                            -- We replace each line end with a line end plus a tab to nest the code properly
                            + REPLACE(@targetRecordCheck, @lineEnd, @lineEnd + @tabSpace)
        -- add key validation check
                            --
                            + @lineEnd
                            -- We replace each line end with a line end plus a tab to nest the code properly
                            + REPLACE(@deleteKeyValidationCheck, @lineEnd, @lineEnd + @tabSpace)
                            --
                            + @lineEnd
                            + @tabSpace
                            + N'DELETE '
                            + @quotedSchemaQualifiedName
        -- Add WHERE clause and close out proc
                            --
                            + @lineEnd
                            + @tabSpace
                            -- We replace each line end with a line end plus a tab to nest the code properly
                            + REPLACE(@targetWhereClause, @lineEnd, @lineEnd + @tabSpace)
                            + N';'
                            --
                            + @lineEnd
                            + N'END;'
                            --
                            + @lineEnd;

        -- present delete proc
        set @crudPresentationStatement =    @crudPresentationStatement
                                            + @deleteProc
                                            + @lineEnd
                                            + N'GO'
                                            + @lineEnd;

        --------------------------------------------------------------------------------------------------------------
        -- write SSDL function for delete proc
        --------------------------------------------------------------------------------------------------------------
        set @thisSsdlFunction = N'<Function Name="'
                                + @deleteProcName
                                + N'" Aggregate="false" BuiltIn="false" NiladicFunction="false" IsComposable="false" ParameterTypeSemantics="AllowImplicitConversion" Schema="'
                                + @databaseAbstractionSchema
                                + N'">'
                                + @lineEnd
                                --
                                + REPLACE(REPLACE(REPLACE(
                                                    (    
                                                        select      @tab
                                                                    + '<Parameter Name="'
                                                                    + [name]
                                                                    + N'" Type="'
                                                                    + [dbType]
                                                                    + N'" Mode="In"'
                                                                    + case -- using types.name to help readability at performance cost
                                                                        when [dbType] in ( N'nchar', N'nvarchar', N'char', N'varchar', N'binary', N'varbinary' )
                                                                            then N' MaxLength="' + [maxLength] + N'"'
                                                                        when [dbType] in ( N'decimal', N'numeric' )
                                                                            then N' Precision="' + [precision] + N'" Scale="' + [scale] + N'"'
                                                                        when [dbType] in ( N'float', N'datetime2', N'datetimeoffset' )
                                                                            then N' Precision="' + [precision] + N'"'
                                                                        else ''
                                                                      end
                                                                    + @xmlElementClose
                                                                    + @lineEnd
                                                        from        @columnInfo
                                                        where       [isDeleteParameter] = CAST(1 as bit)
                                                        order by    [columnId]
                                                        for xml path('')
                                                    ) -- end of SELECT
                                                    , N'&#x0D;', NCHAR(13)
                                                ) -- end of REPLACE carriage return
                                                , N'&lt;', N'<'
                                            ) -- end of REPLACE less than
                                            , N'&gt;', N'>'
                                        ) -- end of REPLACE greater than
                                --
                                + N'</Function>'
                                + @lineEnd;

        -- add update function to SSDL functions
        set @ssdlFunctions  =   @ssdlFunctions
                                + @thisSsdlFunction;
    end; -- end IF @isReadonly = CAST(0 as bit)
    
    if @debugMode = CAST(1 as bit)
    begin;
        select  [coveringView]  = @coveringView,
                [insertProc]    = @createProc,
                [updateProc]    = @updateProc,
                [deleteProc]    = @deleteProc;
                
        select  [CRUD object script in progress]    = @crudPresentationStatement,
                [SSDL Functions in progress]        = @ssdlFunctions;
    end;

--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- ...Write SSDL EntityType and EntitySet
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    set @thisSsdlEntityType =   N'<EntityType Name="store_'
                                + @objectName
                                + N'">'
                                --
                                + @lineEnd
                                + @tab
                                + N'<Key>'
                                --
                                + REPLACE(REPLACE(REPLACE(
                                                    (    
                                                        select      @lineEnd
                                                                    + REPLICATE(@tab, 2)
                                                                    + '<PropertyRef Name="'
                                                                    + [Name]
                                                                    + N'"'
                                                                    + @xmlElementClose
                                                        from        @columnInfo
                                                        where       [pkIndexId] is not null
                                                        order by    [pkIndexId]
                                                        for xml path('')
                                                    ) -- end of SELECT
                                                    , N'&#x0D;', NCHAR(13)
                                                ) -- end of REPLACE carriage return
                                            , N'&lt;', N'<'
                                            ) -- end of REPLACE less than
                                        , N'&gt;', N'>'
                                        ) -- end of REPLACE greater than
                                --
                                + @lineEnd
                                + @tab
                                + N'</Key>'
                                --
                                + REPLACE(REPLACE(REPLACE(
                                                    (    
                                                        select      @lineEnd
                                                                    + @tab
                                                                    + '<Property Name="'
                                                                    + [name]
                                                                    + N'" Type="'
                                                                    + [dbType]
                                                                    + N'" StoreGeneratedPattern="'
                                                                    + case
                                                                        when [isIdentity] = CAST(1 as bit)
                                                                            then N'Identity'
                                                                        when [isCalculated] = CAST(1 as bit)
                                                                            then N'Computed'
                                                                        else N'None'
                                                                      end
                                                                    + N'" Nullable="'
                                                                    + [isNullable]
                                                                    + N'"'
                                                                    + case
                                                                        when [maxLength] is not null
                                                                            then N' MaxLength="' + [maxLength] + N'"'
                                                                        when [dbType] in ( N'text', N'ntext', N'image', N'xml' )
                                                                            then N' MaxLength="Max"'
                                                                        when [dbType] in ( N'timestamp', N'rowversion' )
                                                                            then N' MaxLength="8"'
                                                                        else N''
                                                                      end
                                                                    + case
                                                                        when ISNULL([isFixedLength], N'false') = N'true'
                                                                            then N' FixedLength="true"'
                                                                        else N''
                                                                      end
                                                                    + case
                                                                        when [precision] is not null
                                                                            then N' Precision="' + [precision] + N'"'
                                                                        else N''
                                                                      end
                                                                    + case
                                                                        when [scale] is not null
                                                                            then N' Scale="' + [scale] + N'"'
                                                                        else N''
                                                                      end
                                                                    + case
                                                                        when [dbType] in ( N'char', N'varchar', N'text' )
                                                                            then N' Unicode="false"'
                                                                        when [dbType] in ( N'nchar', N'ntext' )
                                                                            then N' Unicode="true"'
                                                                        else N''
                                                                      end
                                                                    + @xmlElementClose
                                                        from        @columnInfo
                                                        order by    [columnId]
                                                        for xml path(N'')
                                                    ) -- end of SELECT
                                                    , N'&#x0D;', NCHAR(13)
                                                ) -- end of REPLACE carriage return
                                            , N'&lt;', N'<'
                                            ) -- end of REPLACE less than
                                        , N'&gt;', N'>'
                                        ) -- end of REPLACE greater than
                                --
                                + @lineEnd
                                + N'</EntityType>'
                                --
                                + @lineEnd;
    
    -- add @thisSsdlEntityType to full set
    set @ssdlEntityTypes =  @ssdlEntityTypes
                            + @thisSsdlEntityType;

    set @thisSsdlEntitySet =    N'<EntitySet Name="store_'
                                + @objectName
                                + N's" EntityType="Self.store_'
                                + @objectName
                                + N'" store:Type="Views" store:Schema="'
                                + @databaseAbstractionSchema
                                + '">'
                                --
                                + @lineEnd
                                + @tab
                                + N'<DefiningQuery>'
                                --
                                + @lineEnd
                                + REPLICATE(@tab, 2)
                                + N'SELECT'
                                --
                                + STUFF(REPLACE(STUFF(
                                            (    
                                                select      @lineEnd -- 7 characters because NCHAR(13) becomes '&#x0D;'
                                                            + REPLICATE(@tabSpace, 3)
                                                            + ', '
                                                            + QUOTENAME([name], N'[')
                                                from        @columnInfo
                                                order by    [columnId]
                                                for xml path('')
                                            ) -- end of SELECT
                                            , 1, 21, '  '
                                        ) -- end of inner STUFF
                                        , N'&#x0D;', NCHAR(13)
                                    ) -- end of REPLACE
                                    , 1, LEN(@tabSpace), N''
                                ) -- end of outer STUFF
                                --
                                + @lineEnd
                                + REPLICATE(@tab, 2)
                                + N'FROM '
                                + QUOTENAME(@databaseAbstractionSchema, N'[')
                                + N'.'
                                + QUOTENAME(@coveringViewName, N'[')
                                + N';'
                                --
                                + @lineEnd
                                + @tab
                                + N'</DefiningQuery>'
                                --
                                + @lineEnd
                                + N'</EntitySet>'
                                --
                                + @lineEnd;

    -- add @thisSsdlEntitySet to full set
    set @ssdlEntitySets =   @ssdlEntitySets
                            + @thisSsdlEntitySet;

--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- ...Write CSDL EntityType and EntitySet
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    set @thisCsdlEntityType =   N'<EntityType Name="'
                                + @objectName
                                + N'">'
                                --
                                + @lineEnd
                                + @tab
                                + N'<Key>'
                                --
                                + REPLACE(REPLACE(REPLACE(
                                                    (    
                                                        select      @lineEnd
                                                                    + REPLICATE(@tab, 2)
                                                                    + '<PropertyRef Name="'
                                                                    + [Name]
                                                                    + N'"'
                                                                    + @xmlElementClose
                                                        from        @columnInfo
                                                        where       [pkIndexId] is not null
                                                        order by    [pkIndexId]
                                                        for xml path('')
                                                    ) -- end of SELECT
                                                    , N'&#x0D;', NCHAR(13)
                                                ) -- end of REPLACE carriage return
                                            , N'&lt;', N'<'
                                            ) -- end of REPLACE less than
                                        , N'&gt;', N'>'
                                        ) -- end of REPLACE greater than
                                --
                                + @lineEnd
                                + @tab
                                + N'</Key>'
                                --
                                + REPLACE(REPLACE(REPLACE(
                                                    (    
                                                        select      @lineEnd
                                                                    + @tab
                                                                    + '<Property Name="'
                                                                    + [name]
                                                                    + N'" Type="'
                                                                    + [appType]
                                                                    + N'" Nullable="'
                                                                    + [isNullable]
                                                                    + N'"'
                                                                    + case
                                                                        when [maxLength] is not null
                                                                            then N' MaxLength="' + [maxLength] + N'"'
                                                                        when [dbType] in ( N'text', N'ntext', N'image', N'xml' )
                                                                            then N' MaxLength="Max"'
                                                                        when [dbType] in ( N'timestamp', N'rowversion' )
                                                                            then N' MaxLength="8"'
                                                                        else N''
                                                                      end
                                                                    + case
                                                                        when [isFixedLength] is not null
                                                                            then N' FixedLength="' + [isFixedLength] + N'"'
                                                                        else N''
                                                                      end
                                                                    + case
                                                                        when [precision] is not null
                                                                            then N' Precision="' + [precision] + N'"'
                                                                        when [dbType] = N'datetime'
                                                                            then N' Precision="3"'
                                                                        when [dbType] in ( N'date', N'smalldatetime' )
                                                                            then N' Precision="0"'
                                                                        when [dbType] = N'money'
                                                                            then N' Precision="19"'
                                                                        when [dbType] = N'smallmoney'
                                                                            then N' Precision="10"'
                                                                        else N''
                                                                      end
                                                                    + case
                                                                        when [scale] is not null
                                                                            then N' Scale="' + [scale] + N'"'
                                                                        else N''
                                                                      end
                                                                    + case
                                                                        when [isUnicode] is not null
                                                                            then N' Unicode="' + [isUnicode] + N'"'
                                                                        else N''
                                                                      end
                                                                    + case
                                                                        when [isIdentity] = CAST(1 as bit)
                                                                            then N' annotation:StoreGeneratedPattern="Identity"'
                                                                        when [isCalculated] = CAST(1 as bit)
                                                                            then N' annotation:StoreGeneratedPattern="Computed"'
                                                                        when [dbType] in ( N'timestamp', N'rowversion' )
                                                                            then N' annotation:StoreGeneratedPattern="Computed"'
                                                                        else N''
                                                                      end
                                                                    + @xmlElementClose
                                                        from        @columnInfo
                                                        order by    [columnId]
                                                        for xml path(N'')
                                                    ) -- end of SELECT
                                                    , N'&#x0D;', NCHAR(13)
                                                ) -- end of REPLACE carriage return
                                            , N'&lt;', N'<'
                                            ) -- end of REPLACE less than
                                        , N'&gt;', N'>'
                                        ) -- end of REPLACE greater than
                                --
                                + REPLACE(@thisCsdlNavigationProperties, @lineEnd, @lineEnd + @tab)
                                --
                                + @lineEnd
                                + N'</EntityType>'
                                --
                                + @lineEnd;
    
    -- add @thisCsdlEntityType to full set
    set @csdlEntityTypes    =   @csdlEntityTypes
                                + @thisCsdlEntityType;
    
    set @thisCsdlEntitySet  =   N'<EntitySet Name="'
                                + @objectName
                                + N's" EntityType="Self.'
                                + @objectName
                                + N'"'
                                + @xmlElementClose
                                --
                                + @lineEnd;
    
    -- add @thisCsdlEntitySet to full set
    set @csdlEntitySets =   @csdlEntitySets
                            + @thisCsdlEntitySet;

    if @debugMode = CAST(1 as bit)
    begin;
        select  [ssdlEntityType]    = @thisSsdlEntityType,
                [ssdlEntitySet]     = @thisSsdlEntitySet,
                [csdlEntityType]    = @thisCsdlEntityType,
                [csdlEntitySet]     = @thisCsdlEntitySet;
    end;

--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- ...Write MSL EntitySetMapping
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    set @thisMslEntitySetMapping    =   N'<EntitySetMapping Name="'
                                        + @objectName
                                        + N's">'
                                        --------------------------------------------------------------------------
                                        -- Mapping Fragment
                                        --------------------------------------------------------------------------
                                        --
                                        + @lineEnd
                                        + @tab
                                        + N'<EntityTypeMapping TypeName="concept.'
                                        + @objectName
                                        + N'">'
                                        --
                                        + @lineEnd
                                        + REPLICATE(@tab, 2)
                                        + N'<MappingFragment StoreEntitySet="store_'
                                        + @objectName
                                        + N's">'
                                        --
                                        + REPLACE(REPLACE(REPLACE(
                                                            (    
                                                                select      @lineEnd
                                                                            + REPLICATE(@tab, 3)
                                                                            + '<ScalarProperty Name="'
                                                                            + [Name]
                                                                            + N'" ColumnName="'
                                                                            + [Name]
                                                                            + N'"'
                                                                            + @xmlElementClose
                                                                from        @columnInfo
                                                                order by    [columnId]
                                                                for xml path('')
                                                            ) -- end of SELECT
                                                            , N'&#x0D;', NCHAR(13)
                                                        ) -- end of REPLACE carriage return
                                                    , N'&lt;', N'<'
                                                    ) -- end of REPLACE less than
                                                , N'&gt;', N'>'
                                                ) -- end of REPLACE greater than
                                        --
                                        + @lineEnd
                                        + REPLICATE(@tab, 2)
                                        + N'</MappingFragment>'
                                        --
                                        + @lineEnd
                                        + @tab
                                        + N'</EntityTypeMapping>'
                                        --
                                        -- We do not add modification function info for read-only tables.
                                        + case
                                            when @isReadOnly = CAST(1 as bit)
                                                then N''
                                            else    @lineEnd
                                                    + @tab
                                                    + N'<EntityTypeMapping TypeName="concept.'
                                                    + @objectName
                                                    + N'">'
                                                    --
                                                    + @lineEnd
                                                    + REPLICATE(@tab, 2)
                                                    + N'<ModificationFunctionMapping>'
                                                    --------------------------------------------------------------------------
                                                    -- Insert Function
                                                    --------------------------------------------------------------------------
                                                    --
                                                    + @lineEnd
                                                    + REPLICATE(@tab, 3)
                                                    + N'<InsertFunction FunctionName="store.'
                                                    + @insertProcName
                                                    + N'">'
                                                    --
                                                    + REPLACE(REPLACE(REPLACE(
                                                                        (    
                                                                            select      @lineEnd
                                                                                        + REPLICATE(@tab, 4)
                                                                                        + '<ScalarProperty Name="'
                                                                                        + [Name]
                                                                                        + N'" ParameterName="'
                                                                                        + [Name]
                                                                                        + N'"'
                                                                                        + @xmlElementClose
                                                                            from        @columnInfo
                                                                            where       [isInsertParameter] = CAST(1 as bit)
                                                                            order by    [columnId]
                                                                            for xml path('')
                                                                        ) -- end of SELECT
                                                                        , N'&#x0D;', NCHAR(13)
                                                                    ) -- end of REPLACE carriage return
                                                                , N'&lt;', N'<'
                                                                ) -- end of REPLACE less than
                                                            , N'&gt;', N'>'
                                                            ) -- end of REPLACE greater than
                                                    --
                                                    -- We need the ISNULL in case no column passes the filter to avoid NULL
                                                    -- concatenation issues.
                                                    + ISNULL(REPLACE(REPLACE(REPLACE(
                                                                            (    
                                                                                select      @lineEnd
                                                                                            + REPLICATE(@tab, 4)
                                                                                            + '<ResultBinding Name="'
                                                                                            + [Name]
                                                                                            + N'" ColumnName="'
                                                                                            + [Name]
                                                                                            + N'"'
                                                                                            + @xmlElementClose
                                                                                from        @columnInfo
                                                                                where       [isInsertParameter] is null
                                                                                order by    [columnId]
                                                                                for xml path('')
                                                                            ) -- end of SELECT
                                                                            , N'&#x0D;', NCHAR(13)
                                                                        ) -- end of REPLACE carriage return
                                                                    , N'&lt;', N'<'
                                                                    ) -- end of REPLACE less than
                                                                , N'&gt;', N'>'
                                                                ) -- end of REPLACE greater than
                                                            , N''
                                                            ) -- end of ISNULL
                                                    --
                                                    + @lineEnd
                                                    + REPLICATE(@tab, 3)
                                                    + N'</InsertFunction>'
                                                    --------------------------------------------------------------------------
                                                    -- Update Function
                                                    --------------------------------------------------------------------------
                                                    --
                                                    + @lineEnd
                                                    + REPLICATE(@tab, 3)
                                                    + N'<UpdateFunction FunctionName="store.'
                                                    + @updateProcName
                                                    + N'">'
                                                    --
                                                    + REPLACE(REPLACE(REPLACE(
                                                                        (    
                                                                            select      @lineEnd
                                                                                        + REPLICATE(@tab, 4)
                                                                                        + '<ScalarProperty Name="'
                                                                                        + [Name]
                                                                                        + N'" ParameterName="'
                                                                                        + [Name]
                                                                                        + N'" Version="Current"'
                                                                                        + @xmlElementClose
                                                                            from        @columnInfo
                                                                            where       [isUpdateParameter] = CAST(1 as bit)
                                                                            order by    [columnId]
                                                                            for xml path('')
                                                                        ) -- end of SELECT
                                                                        , N'&#x0D;', NCHAR(13)
                                                                    ) -- end of REPLACE carriage return
                                                                , N'&lt;', N'<'
                                                                ) -- end of REPLACE less than
                                                            , N'&gt;', N'>'
                                                            ) -- end of REPLACE greater than
                                                    --
                                                    + ISNULL(REPLACE(REPLACE(REPLACE(
                                                                            (    
                                                                                select      @lineEnd
                                                                                            + REPLICATE(@tab, 4)
                                                                                            + '<ResultBinding Name="'
                                                                                            + [Name]
                                                                                            + N'" ColumnName="'
                                                                                            + [Name]
                                                                                            + N'"'
                                                                                            + @xmlElementClose
                                                                                from        @columnInfo
                                                                                where       [isUpdateParameter] is null
                                                                                order by    [columnId]
                                                                                for xml path('')
                                                                            ) -- end of SELECT
                                                                            , N'&#x0D;', NCHAR(13)
                                                                        ) -- end of REPLACE carriage return
                                                                    , N'&lt;', N'<'
                                                                    ) -- end of REPLACE less than
                                                                , N'&gt;', N'>'
                                                                ) -- end of REPLACE greater than
                                                            , N''
                                                            ) -- end of ISNULL
                                                    --
                                                    + @lineEnd
                                                    + REPLICATE(@tab, 3)
                                                    + N'</UpdateFunction>'
                                                    --------------------------------------------------------------------------
                                                    -- Delete Function
                                                    --------------------------------------------------------------------------
                                                    --
                                                    + @lineEnd
                                                    + REPLICATE(@tab, 3)
                                                    + N'<DeleteFunction FunctionName="store.'
                                                    + @deleteProcName
                                                    + N'">'
                                                    --
                                                    + REPLACE(REPLACE(REPLACE(
                                                                        (    
                                                                            select      @lineEnd
                                                                                        + REPLICATE(@tab, 4)
                                                                                        + '<ScalarProperty Name="'
                                                                                        + [Name]
                                                                                        + N'" ParameterName="'
                                                                                        + [Name]
                                                                                        + N'"'
                                                                                        + @xmlElementClose
                                                                            from        @columnInfo
                                                                            where       [isDeleteParameter] = CAST(1 as bit)
                                                                            order by    [pkIndexId]
                                                                            for xml path('')
                                                                        ) -- end of SELECT
                                                                        , N'&#x0D;', NCHAR(13)
                                                                    ) -- end of REPLACE carriage return
                                                                , N'&lt;', N'<'
                                                                ) -- end of REPLACE less than
                                                            , N'&gt;', N'>'
                                                            ) -- end of REPLACE greater than
                                                    --
                                                    + @lineEnd
                                                    + REPLICATE(@tab, 3)
                                                    + N'</DeleteFunction>'
                                                    --
                                                    + @lineEnd
                                                    + REPLICATE(@tab, 2)
                                                    + N'</ModificationFunctionMapping>'
                                                    --
                                                    + @lineEnd
                                                    + @tab
                                                    + N'</EntityTypeMapping>'
                                          end -- end modification function mapping CASE
                                        --
                                        + @lineEnd
                                        + N'</EntitySetMapping>'
                                        --
                                        + @lineEnd;

    -- add @thisMslEntitySetMapping to full set
    set @mslEntitySetMappings   =   @mslEntitySetMappings
                                    + @thisMslEntitySetMapping;

    --============================================================================================================
    -- Proceed to the next table
    --============================================================================================================
    fetch next from tableCursor
    into @objectId, @quotedSchemaQualifiedName, @isEverFkParent, @isEverFkChild, @isReadOnly, @coveringViewName, @insertProcName, @updateProcName, @deleteProcName;

end;

close tableCursor;
deallocate tableCursor;

--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- Build .edmx from XML components
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
set @edmxPresentationStatement  =   N'<?xml version="1.0" encoding="utf-8"?>'
                                    --
                                    + @lineEnd
	                                + N'<edmx:Edmx Version="3.0" xmlns:edmx="http://schemas.microsoft.com/ado/2009/11/edmx">'
                                    --
                                    + N'<!-- This CSDL Schema was automatically generated based on table definitions in '
                                    + @databaseName
                                    + N' on '
                                    + @@SERVERNAME
                                    + N' as of '
                                    + CONVERT(nvarchar(27), @executionStart, 121)
                                    + N' UTC by '
                                    + ORIGINAL_LOGIN()
                                    + N'. -->'
                                    --
                                    + @lineEnd
                                    + @tab
	                                + N'<!-- EF Runtime content -->'
                                    --
                                    + @lineEnd
	                                + @tab
	                                + N'<edmx:Runtime>'
                                    ------------------------------------------------------------------------------
                                    -- SSDL
                                    ------------------------------------------------------------------------------
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 2)
                                    + N'<!-- SSDL content -->'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 2)
                                    + N'<edmx:StorageModels>'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 3)
                                    + N'<Schema Namespace="'
                                    + @databaseName
                                    -- ProviderManifestToken sets the SQL Server version
                                    + N'Model.Store" Provider="System.Data.SqlClient" ProviderManifestToken="'
                                    + @sqlServerVersionToken
                                    + '" Alias="Self"'
                                    + N' xmlns:store="http://schemas.microsoft.com/ado/2007/12/edm/EntityStoreSchemaGenerator"'
                                    + N' xmlns:customannotation="http://schemas.microsoft.com/ado/2013/11/edm/customannotation"'
                                    + N' xmlns="http://schemas.microsoft.com/ado/2009/11/edm/ssdl">'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    -- We replace each line end with a line end plus extra tabs to nest code properly
                                    + REPLACE(SUBSTRING(@ssdlEntityTypes
                                            , 1, LEN(@ssdlEntityTypes) - LEN(@lineEnd)
                                            ) -- end of SUBSTRING
                                        , @lineEnd, @lineEnd + REPLICATE(@tab, 4)
                                        ) -- end of REPLACE
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    + N'<EntityContainer Name="store_'
                                    + @databaseName
                                    + N'StoreContainer">'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 5)
                                    + REPLACE(SUBSTRING(@ssdlEntitySets
                                            , 1, LEN(@ssdlEntitySets) - LEN(@lineEnd)
                                            ) -- end of SUBSTRING
                                        , @lineEnd, @lineEnd + REPLICATE(@tab, 5)
                                        ) -- end of REPLACE
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    + N'</EntityContainer>'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    -- We replace each line end with a line end plus extra tabs to nest code properly
                                    + REPLACE(SUBSTRING(@ssdlFunctions
                                            , 1, LEN(@ssdlFunctions) - LEN(@lineEnd)
                                            )
                                        , @lineEnd, @lineEnd + REPLICATE(@tab, 4)
                                        )
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 3)
                                    + N'</Schema>'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 2)
                                    + N'</edmx:StorageModels>'
                                    ------------------------------------------------------------------------------
                                    -- CSDL
                                    ------------------------------------------------------------------------------
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 2)
                                    + N'<!-- CSDL content -->'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 2)
                                    + N'<edmx:ConceptualModels>'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 3)
                                    + N'<Schema Namespace="'
                                    + @databaseName
                                    -- ProviderManifestToken sets the SQL Server version
                                    + N'Model" Alias="Self" annotation:UseStrongSpatialTypes="false"'
                                    + N' xmlns:annotation="http://schemas.microsoft.com/ado/2009/02/edm/annotation" '
                                    + N' xmlns:customannotation="http://schemas.microsoft.com/ado/2013/11/edm/customannotation"'
                                    + N' xmlns="http://schemas.microsoft.com/ado/2009/11/edm">'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    -- We replace each line end with a line end plus extra tabs to nest code properly
                                    + REPLACE(SUBSTRING(@csdlEntityTypes
                                            , 1, LEN(@csdlEntityTypes) - LEN(@lineEnd)
                                            ) -- end of SUBSTRING
                                        , @lineEnd, @lineEnd + REPLICATE(@tab, 4)
                                        ) -- end of REPLACE
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    -- We replace each line end with a line end plus extra tabs to nest code properly
                                    + REPLACE(SUBSTRING(@csdlAssociations
                                            , 1, LEN(@csdlAssociations) - LEN(@lineEnd)
                                            ) -- end of SUBSTRING
                                        , @lineEnd, @lineEnd + REPLICATE(@tab, 4)
                                        ) -- end of REPLACE
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    + N'<EntityContainer Name="'
                                    + @databaseName
                                    + N'StoreContainer">'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 5)
                                    + REPLACE(SUBSTRING(@csdlEntitySets
                                            , 1, LEN(@csdlEntitySets) - LEN(@lineEnd)
                                            ) -- end of SUBSTRING
                                        , @lineEnd, @lineEnd + REPLICATE(@tab, 5)
                                        ) -- end of REPLACE
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 5)
                                    + REPLACE(SUBSTRING(@csdlAssociationSets
                                            , 1, LEN(@csdlAssociationSets) - LEN(@lineEnd)
                                            ) -- end of SUBSTRING
                                        , @lineEnd, @lineEnd + REPLICATE(@tab, 5)
                                        ) -- end of REPLACE
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    + N'</EntityContainer>'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 3)
                                    + N'</Schema>'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 2)
                                    + N'</edmx:ConceptualModels>'
                                    ------------------------------------------------------------------------------
                                    -- MSL
                                    ------------------------------------------------------------------------------
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 2)
                                    + N'<!-- MSL content -->'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 2)
                                    + N'<edmx:Mappings>'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 3)
                                    + N'<Mapping Space="C-S" xmlns="http://schemas.microsoft.com/ado/2009/11/mapping/cs">'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    + N'<Alias Key="store" Value="'
                                    + @databaseName
                                    + N'Model.Store"'
                                    + @xmlElementClose
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    + N'<Alias Key="concept" Value="'
                                    + @databaseName
                                    + N'Model"'
                                    + @xmlElementClose
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    + N'<EntityContainerMapping StorageEntityContainer="store_'
                                    + @databaseName
                                    + N'StoreContainer" CdmEntityContainer="'
                                    + @databaseName
                                    + N'StoreContainer">'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 5)
                                    + REPLACE(SUBSTRING(@mslEntitySetMappings
                                            , 1, LEN(@mslEntitySetMappings) - LEN(@lineEnd)
                                            ) -- end of SUBSTRING
                                            , @lineEnd, @lineEnd + REPLICATE(@tab, 5)
                                        ) -- end of REPLACE
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    + N'</EntityContainerMapping>'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 3)
                                    + N'</Mapping>'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 2)
                                    + N'</edmx:Mappings>'
                                    --
                                    + @lineEnd
                                    + @tab
                                    + N'</edmx:Runtime>'
                                    ------------------------------------------------------------------------------
                                    -- Designer
                                    ------------------------------------------------------------------------------
                                    -- This is entirely boilerplate taken from code generated by Visual Studio
                                    -- when using the EDM wizard.
                                    --
                                    + @lineEnd
                                    + @tab
                                    + N'<!-- EF Designer content (DO NOT EDIT MANUALLY BELOW HERE) -->'
                                    --
                                    + @lineEnd
                                    + @tab
                                    + N'<Designer xmlns="http://schemas.microsoft.com/ado/2009/11/edmx">'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 2)
                                    + N'<Connection>'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 3)
                                    + N'<DesignerInfoPropertySet>'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    + N'<DesignerProperty Name="MetadataArtifactProcessing" Value="EmbedInOutputAssembly" />'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 3)
                                    + N'</DesignerInfoPropertySet>'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 2)
                                    + N'</Connection>'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 2)
                                    + N'<Options>'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 3)
                                    + N'<DesignerInfoPropertySet>'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    + N'<DesignerProperty Name="ValidateOnBuild" Value="true" />'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    + N'<DesignerProperty Name="EnablePluralization" Value="true" />'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    + N'<DesignerProperty Name="IncludeForeignKeysInModel" Value="true" />'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    + N'<DesignerProperty Name="UseLegacyProvider" Value="false" />'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 4)
                                    + N'<DesignerProperty Name="CodeGenerationStrategy" Value="None" />'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 3)
                                    + N'</DesignerInfoPropertySet>'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 2)
                                    + N'</Options>'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 2)
                                    + N'<!-- Diagram content (shape and connector positions) -->'
                                    --
                                    + @lineEnd
                                    + REPLICATE(@tab, 2)
                                    + N'<Diagrams></Diagrams>'
                                    --
                                    + @lineEnd
                                    + @tab
                                    + N'</Designer>'
                                    --
                                    + @lineEnd
                                    + N'</edmx:Edmx>'
                                    --
                                    + @lineEnd;

if @debugMode = CAST(1 as bit)
begin;
    select  [ssdlEntityContainer]    = @ssdlEntityContainer,
            [csdlEntityContainer]    = @csdlEntityContainer;
end;

--////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- Present code
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\

select  [crudObjectCreationStatements]  = @crudPresentationStatement,
        [edmxPresentationStatement]     = @edmxPresentationStatement;

if @debugMode = CAST(1 as bit)
begin;
    select  [ssdlEntityTypes]       = @ssdlEntityTypes,
            [ssdlAssociations]      = @ssdlAssociations,
            [ssdlEntitySets]        = @ssdlEntitySets,
            [ssdlAssociationSets]   = @ssdlAssociationSets,
            [ssdlFunctions]         = @ssdlFunctions,
            [csdlEntityTypes]       = @csdlEntityTypes,
            [csdlAssociations]      = @csdlAssociations,
            [csdlEntitySets]        = @csdlEntitySets,
            [csdlAssociationSets]   = @csdlAssociationSets,
            [mslEntitySetMappings]  = @mslEntitySetMappings;
end;

set @executionEnd = SYSUTCDATETIME();
print   N'AbstractionGenerator script execution stop: '
        + CONVERT(nvarchar(27), @executionEnd, 121)
        + N' UTC. Duration: '
        + CAST(DATEDIFF(ms, @executionStart, @executionEnd) as nvarchar(11))
        + N' milliseconds ('
        + CAST(DATEDIFF(ns, @executionStart, @executionEnd) as nvarchar(11))
        + N' nanoseconds)';

-- If we're in demo mode, clean up after ourselves.
if @demoMode = CAST(1 as bit)
begin;
    select [DemoModeEngaged] = N'!!! DEMO MODE CLEANUP !!!'
    print   N'!!!!!!!!!!!!!!!!!!!!!!!!!'
            + N'!!! DEMO MODE CLEANUP !!!'
            + N'!!!!!!!!!!!!!!!!!!!!!!!!!';

    if OBJECT_ID(N'abstractionDemo.twoMemberFk', N'U') is not null
    begin;
        print N'Dropping table [abstractionDemo].[twoMemberFk]...';
        drop table [abstractionDemo].[twoMemberFk];
        print N'...done!';
    end;
    else begin;
        print N'Table [abstractionDemo].[twoMemberFk] does not exist.';
    end;

    if OBJECT_ID(N'abstractionDemo.externalReference', N'U') is not null
    begin;
        print N'Dropping table [abstractionDemo].[externalReference]...';
    drop table [abstractionDemo].[externalReference];
        print N'...done!';
    end;
    else begin;
        print N'Table [abstractionDemo].[externalReference] does not exist.';
    end;
    
    if OBJECT_ID(N'abstractionDemo.twoMemberPk', N'U') is not null
    begin;
        print N'Dropping table [abstractionDemo].[twoMemberPk]...';
    drop table [abstractionDemo].[twoMemberPk];
        print N'...done!';
    end;
    else begin;
        print N'Table [abstractionDemo].[twoMemberPk] does not exist.';
    end;
    
    if SCHEMA_ID(N'abstractionDemo') is not null
    begin;
        print N'Dropping schema [abstractionDemo]...';
    drop schema [abstractionDemo];
        print N'...done!';
    end;
    else begin;
        print N'Schema [abstractionDemo] does not exist.';
    end;
end;
