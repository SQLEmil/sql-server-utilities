-- This script will generate INSERT statement wrappers for VALUES elements for a
-- given list of tables and any tables referenced by those tables through foreign keys.
-- It will also generate a script that in turn generates VALUES elements for the table.
-- Results are returned in the order of the dependencies, i.e., they are in the order
-- in which the INSERT statements must be run to honor the foreign key constraints.

set nocount on;

--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- Set these values to affect script execution
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
declare @fkAwareness            tinyint = 1, -- 1 = dynamically finds table dependencies and adds tables
        @includeDeleteStatement tinyint = 1; -- 1 = includes conditional delete statements for table set, requires @fkAwareness = 1
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

declare @tableListSubmitted table (
    schemaQualifiedObjectName	nvarchar(128)	null
    );

insert @tableListSubmitted ( schemaQualifiedObjectName )
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- Add all the tables for which you'd like to generate scripts as ( 'schemaName.tableName' )
--                                                             or ( '[schemaName].[tableName]' )
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
values	('staging.VendorPart')
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

--=======================================================================
-- Here on down is the guts of the code. If you just want to generate scripts, no
-- need to read further.
--========================================================================
declare	@objectId					int,
        @columnId					int,
        @quotedSchemaQualifiedName	nvarchar(261), -- two sysnames, four brackets, and a period
        @hasIdentityFlag		    tinyint,
        @hasFkFlag                  tinyint,
        @addedForFkFlag             tinyint,
        @dependencyGroupCounter     int, -- used to count dependency depth
        @quotedColumnName			nvarchar(128), -- including to prevent need for lookups in nested cursor
        @userTypeId					int,
        @userTypeName				nvarchar(128), -- including to prevent need for lookups in nested cursor
        @isNullable					bit,
        @columnNumber				int,
        @lineEnd					nchar(2)		= NCHAR(13) + NCHAR(10),
        @tab						nchar(1)		= NCHAR(9),
        @commaDelimiter				nchar(7)		= N'+ N'', ''',
        @nFrontQuote				nchar(9)		= N'N''N'''''' + ', -- for leading unicode string columns
        @frontQuote					nchar(8)		= N'N'''''''' + ', -- for leading ASCII and hexadecimal string columns
        @endQuote					nchar(8)		= N' + N''''''''', -- for closing string columns
        @valuePlaceholder			nchar(12)		= N'{columnPlaceholder}', -- supports REPLACE statements
        @frontWrapper				nvarchar(max), -- beginning of INSERT statement
        @backWrapper				nvarchar(max), -- end of INSERT statement
        @fkListDisplay              nvarchar(max), -- holds list of FK's on table with column info
        @workingColumn				nvarchar(max), -- space to build individual column statement
        @valueGeneratorStatement	nvarchar(max), -- script to generate VALUE elements
        @presentationStatement		nvarchar(max);

--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--=======================================================================
-- Assemble and order table list
--=======================================================================
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
declare @tableListPresented table (
    quotedSchemaQualifiedName	nvarchar(261)	null,
    objectId					int				null,
    hasFkFlag                   tinyint         null,
    referencedFlag              tinyint         null,
    addedForFkFlag              tinyint         null,
    dependencyGroup             tinyint         null -- this represents the set of tables at a particular depth in the dependency chain, 0 would have no FK's
    );

insert @tableListPresented (
    quotedSchemaQualifiedName,
    objectId,
    addedForFkFlag
    )
select  QUOTENAME(SCHEMA_NAME([schema_id]), '[')
        + N'.'
        + QUOTENAME(name, '[')  as quotedSchemaQualifiedName,
        [object_id]             as objectId,
        0                       as addedForFkFlag -- submitted objects were not added for FK support
from    @tableListSubmitted
        inner join
        -- This OBJECT_ID() call insures we only bring through tables
        sys.objects on objects.[object_id] = OBJECT_ID(schemaQualifiedObjectName, 'U');


if @fkAwareness = 1
begin;
    
    -- Determine if tables have any foreign keys. If so, make sure the referenced tables are
    -- added to the list, and do so recursively
    while exists (  select 1
                    from    @tableListPresented
                            inner join
                            sys.foreign_keys on foreign_keys.parent_object_id = objectId
                    where   not exists ( select 1 from @tableListPresented where objectId = foreign_keys.referenced_object_id )
                  )
    begin;
        
        insert @tableListPresented (
            quotedSchemaQualifiedName,
            objectId,
            referencedFlag,
            addedForFkFlag
            )
        -- We need to use SELECT DISTINCT to avoid adding the same table twice if another table has more
        -- than one foreign key referencing it.
        select distinct QUOTENAME(OBJECT_SCHEMA_NAME(foreign_keys.referenced_object_id), '[')
                        + N'.' 
                        +  QUOTENAME(OBJECT_NAME(foreign_keys.referenced_object_id), '[') as schemaQualifiedObjectName,
                        foreign_keys.referenced_object_id,
                        1 as referencedFlag,
                        1 as addedForFkFlag
        from    sys.foreign_keys
                inner join
                @tableListPresented on objectId = foreign_keys.parent_object_id
        where   not exists ( select 1 from @tableListPresented where objectId = foreign_keys.referenced_object_id );
    
        -- Fill out missing metadata
        if exists ( select 1 from @tableListPresented where hasFkFlag is null )
        begin;
            
            -- Mark all the tables with FK's
            update  @tableListPresented
            set     hasFkFlag = 1
            where   exists ( select 1 from sys.foreign_keys where foreign_keys.parent_object_id = objectId )
                    and
                    hasFkFlag is null;
    
            -- By definition, every record left with NULL does not have an FK
            update  @tableListPresented
            set     hasFkFlag       = 0,
                    dependencyGroup = 0 -- Tables without dependencies are in dependency group 0
            where   hasFkFlag is null;
    
        end;
    
        if exists ( select 1 from @tableListPresented where referencedFlag is null )
        begin;
            
            -- Mark all the referenced tables
            update  @tableListPresented
            set     referencedFlag = 1
            where   exists (    select  1
                                from    sys.foreign_keys
                                where   foreign_keys.referenced_object_id = objectId
                                        and
                                        foreign_keys.parent_object_id in ( select objectId from @tableListPresented )
                           )
                    and
                    referencedFlag is null;
    
            -- By definition, every record left with NULL is not referenced
            update  @tableListPresented
            set     referencedFlag = 0
            where   referencedFlag is null;
    
        end;
    
    end;
    
    -- Initialize dependency group counter and determine dependency groups
    set @dependencyGroupCounter = 0;
    
    while exists ( select 1 from @tableListPresented where dependencyGroup is null )
    begin;
        
        -- Increment dependency group
        set @dependencyGroupCounter = @dependencyGroupCounter + 1;
    
        -- Identify group membership
        update  @tableListPresented
        set     dependencyGroup = @dependencyGroupCounter
        from    @tableListPresented
        where   dependencyGroup is null
                and
                (
                    not exists (
                                    select  referenced_object_id
                                    from    sys.foreign_keys
                                    where   foreign_keys.parent_object_id = objectId
    
                                    except
    
                                    select  objectId
                                    from    @tableListPresented
                                    where   dependencyGroup is not null
                                )
                    or
                    exists  (
                                select  1
                                from    sys.foreign_keys
                                where   foreign_keys.parent_object_id = foreign_keys.referenced_object_id
                                        and
                                        foreign_keys.parent_object_id = objectId
                            )
                );
    
    end;
    
    if @includeDeleteStatement = 1
    begin;
        
        --!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        --=======================================================================
        -- Present ordered conditional deletes for table set
        --=======================================================================
        --!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        select    N'--!!!      --==THIS SCRIPT MUST BE ALTERED TO DO ANYTHING!==--      !!!'
                + @lineEnd
                + N'--!!! This script was generated by code with the intent of being    !!!'
                + @lineEnd
                + N'--!!! altered to specify the data to be deleted and used in a test  !!!'
                + @lineEnd
                + N'--!!! environment. Any data damage or loss caused by this script or !!!'
                + @lineEnd
                + N'--!!! its execution is the responsibility of the executor.          !!!'
                + @lineEnd
                + REPLACE(
                        STUFF(
                                (
                                    select  @lineEnd +
                                            REPLACE(deleteBlock.deleteBlock, N'{objectName}', quotedSchemaQualifiedName)
                                    from    @tableListPresented
                                            cross apply (
                                                            select  N'if exists ( select 1 from {objectName} where 0 = 1 )'
                                                                    + @lineEnd
                                                                    + N'begin;'
                                                                    + @lineEnd
                                                                    + @tab
                                                                    + N'delete {objectName} where 0 = 1;'
                                                                    + @lineEnd
                                                                    + N'end;'
                                                                    + @lineEnd as deleteBlock
                                                        ) as deleteBlock
                                    order by    dependencyGroup desc,
                                                quotedSchemaQualifiedName desc
                                    for xml path ('')
                                ), 1, 7, N'' -- end of STUFF
                            ), N'&#x0D;', NCHAR(13) -- replaces carriage return
                         ) as deleteStatementsForTableSet;
        
    end;
    
end;

--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
--=======================================================================
-- Construct and present statements for each table
--=======================================================================
--!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
declare tableCursor cursor 
    for select      objectId,
                    quotedSchemaQualifiedName,
                    ISNULL(hasFkFlag, 0),
                    ISNULL(addedForFkFlag, 0)
        from        @tableListPresented
        where       objectId is not null
        order by    dependencyGroup,
                    quotedSchemaQualifiedName;

open tableCursor;

fetch next from tableCursor
into @objectId, @quotedSchemaQualifiedName, @hasFkFlag, @addedForFkFlag;

while @@FETCH_STATUS = 0
begin;
    
    -- Initialize the wrapper values and identity flag to avoid old values persisting
    -- across iterations and avoid NULL concatenation issues.
    select  @frontWrapper               = N'',
            @backWrapper                = N'',
            @fkListDisplay              = N'',
            @workingColumn              = N'',
            @valueGeneratorStatement    = N'',
            @presentationStatement      = N'',
            @hasIdentityFlag            = 0;

    -- determine if table has identity value
    if exists (select 1 from sys.identity_columns where [object_id] = @objectId)
    begin;
        
        select @hasIdentityFlag = 1;

    end;

    --!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    --=======================================================================
    -- Build front end wrapper
    --=======================================================================
    --!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    -- If table was added to support foreign key relationships for submitted tables, make note
    if @addedForFkFlag = 1
    begin;
        
        set @frontWrapper = N'-- Table was automatically added to support FK relationships'
                            + @lineEnd;

    end;
    
    -- Begin standard script header
    set	@frontWrapper =	@frontWrapper
                        + N'--============================================================================'
                        + @lineEnd
                        + N'--||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||'
                        + @lineEnd
                        + N'--============================================================================'
                        + @lineEnd
                        + N'-- '
                        + @quotedSchemaQualifiedName
                        + N' test data'
                        + @lineEnd;

    -- If table has any foreign keys, list them out
    if @hasFkFlag = 1
    begin;

        select @frontWrapper =  @frontWrapper
                                + REPLACE(
                                        STUFF(
                                                (
                                                    select      @lineEnd
                                                                + N'--'
                                                                + @tab
                                                                + N'Column(s) ( '
                                                                + parentColumns.parentColumnList
                                                                + N' ) has FK reference to '
                                                                + QUOTENAME(OBJECT_SCHEMA_NAME(foreign_keys.referenced_object_id), '[')
                                                                + N'.'
                                                                + QUOTENAME(OBJECT_NAME(foreign_keys.referenced_object_id), '[')
                                                                + N' ( '
                                                                + referencedColumns.referencedColumnList
                                                                + N' ) - '
                                                                + QUOTENAME(OBJECT_NAME(foreign_keys.[object_id]), '[')
                                                    from        sys.foreign_keys
                                                                cross apply (
                                                                    select STUFF( -- Getting parent columns names using standard FOR XML comma-delimited list pattern
                                                                                    (	
                                                                                        select	N', ' + 
                                                                                                QUOTENAME(columns.name,'[')
                                                                                        from	sys.foreign_key_columns
                                                                                                inner join
                                                                                                sys.columns on  columns.column_id = foreign_key_columns.parent_column_id
                                                                                                                and
                                                                                                                columns.[object_id] = foreign_key_columns.parent_object_id
                                                                                        where   foreign_key_columns.constraint_object_id = foreign_keys.[object_id]
                                                                                        order by	foreign_key_columns.constraint_column_id
                                                                                        for xml path('')
                                                                                    ), 1, 2, ''
                                                                                ) as parentColumnList
                                                                            ) as parentColumns
                                                                cross apply (
                                                                    select STUFF( -- Getting referenced columns names using standard FOR XML comma-delimited list pattern
                                                                                    (	
                                                                                        select	N', ' + 
                                                                                                QUOTENAME(columns.name,'[')
                                                                                        from	sys.foreign_key_columns
                                                                                                inner join
                                                                                                sys.columns on  columns.column_id = foreign_key_columns.referenced_column_id
                                                                                                                and
                                                                                                                columns.[object_id] = foreign_key_columns.referenced_object_id
                                                                                        where   foreign_key_columns.constraint_object_id = foreign_keys.[object_id]
                                                                                        order by	foreign_key_columns.constraint_column_id
                                                                                        for xml path('')
                                                                                    ), 1, 2, ''
                                                                                ) as referencedColumnList
                                                                            ) as referencedColumns
                                                    where       foreign_keys.parent_object_id = @objectId
                                                    order by    foreign_keys.parent_object_id,
                                                                foreign_keys.[object_id]
                                                    for xml path('')
                                                ), 1, 0, N'' -- end of STUFF, nothing is stuffed
                                            ), N'&#x0D;', NCHAR(13) -- replaces carriage return
                                        );

        -- Add a final line end
        set @frontWrapper = @frontWrapper
                            + @lineEnd;

    end;
                            
                            
                            
    -- add bottom bumper
    select	@frontWrapper =	@frontWrapper
                            + N'--============================================================================'
                            + @lineEnd
                            + N'--||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||'
                            + @lineEnd
                            + N'--============================================================================'
                            + @lineEnd;
    
    -- set IDENTITY_INSERT, if necessary
    if @hasIdentityFlag = 1
    begin;
        
        select	@frontWrapper =	@frontWrapper
                                + N'set IDENTITY_INSERT '
                                + @quotedSchemaQualifiedName
                                + N' on;'
                                + @lineEnd;

    end;

    -- basic INSERT beginning
    select	@frontWrapper =	@frontWrapper
                            + N'insert '
                            + @quotedSchemaQualifiedName
                            + N' ('
    
    -- add comma-delimited, quoted column list
    select	@frontWrapper =	@frontWrapper
                            + STUFF(
                                    (	
                                        select	', ' + 
                                                QUOTENAME(columns.name,'[')
                                        from	sys.columns
                                        where	[object_id] = @objectId
                                        order by	columns.column_id
                                        for xml path('')
                                    ), 1, 2, ''
                                );
    
    -- basic INSERT ending
    select	@frontWrapper =	@frontWrapper
                            + N')'
                            + @lineEnd
                            + N'VALUES'
                            + @lineEnd;

    -- present front wrapper
    select	@presentationStatement =	N'select N'''
                                        + REPLACE(@frontWrapper, N'''', N'''''')
                                        + N''' as '
                                        + SCHEMA_NAME([schema_id])
                                        + N'_'
                                        + name
                                        + N'_frontInsertWrapper'
    from	sys.objects
    where	[object_id] = @objectId;

    --!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    --=======================================================================
    -- Build back end wrapper
    --=======================================================================
    --!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    -- terminate INSERT statement
    select	@backWrapper =	N';'
                            + @lineEnd;

    -- set IDENTITY_INSERT, if necessary
    if @hasIdentityFlag = 1
    begin;
        
        select	@backWrapper =	@backWrapper
                                + N'set IDENTITY_INSERT '
                                + @quotedSchemaQualifiedName
                                + N' off;'
                                + @lineEnd;

    end;

    -- terminate batch to help keep transaction size smaller
    select @backWrapper =	@backWrapper
                            + N'go'
                            + @lineEnd;

    -- present back wrapper
    select	@presentationStatement =	@presentationStatement
                                        + N', N'''
                                        + REPLACE(@backWrapper, N'''', N'''''')
                                        + N''' as '
                                        + SCHEMA_NAME([schema_id])
                                        + N'_'
                                        + name
                                        + N'_backInsertWrapper'
    from	sys.objects
    where	[object_id] = @objectId;

    --!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    --=======================================================================
    -- Build value generator
    --=======================================================================
    --!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    -- All value generators start the same:
    set	@valueGeneratorStatement =	N'--============================================================================'
                                    + @lineEnd
                                    + N'--||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||'
                                    + @lineEnd
                                    + N'--============================================================================'
                                    + @lineEnd
                                    + N'-- '
                                    + @quotedSchemaQualifiedName
                                    + N' data scripting'
                                    + @lineEnd
                                    + N'--============================================================================'
                                    + @lineEnd
                                    + N'--||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||'
                                    + @lineEnd
                                    + N'--============================================================================'
                                    + @lineEnd
                                    + N'select'
                                    + @tab
                                    + N'N''( '''
                                    + @lineEnd;
    
    -- In order to build out the value generator, we need to step through the
    -- columns in the table. There's probably a set-based way to do it, but I
    -- haven't quite figured it out.
    declare columnCursor cursor
        for select		columns.column_id,
                        QUOTENAME(columns.name, '['),
                        columns.user_type_id,
                        types.name,
                        columns.is_nullable,
                        ROW_NUMBER() over (order by columns.column_id)
            from		sys.columns
                        inner join
                        sys.types on types.user_type_id = columns.user_type_id
            where		columns.[object_id] = @objectId
            order by	columns.column_id;

    open columnCursor;

    fetch next from columnCursor
        into @columnId, @quotedColumnName, @userTypeId, @userTypeName, @isNullable, @columnNumber;

    while @@FETCH_STATUS = 0
    begin;
        
        -- If this isn't the first column, add a delimiting comma
        if @columnNumber > 1
        begin;
            
            set @valueGeneratorStatement =	@valueGeneratorStatement
                                            + @tab
                                            + @tab
                                            + @commaDelimiter
                                            + @lineEnd;

        end;

        -- If the column is nullable, use the appropriate wrapper. Otherwise,
        -- just use the placeholder.
        if @isNullable = 1
        begin;
            -- NULL handling wrapper
            set	@workingColumn =	@tab
                                    + @tab
                                    + N'+ case'
                                    + @lineEnd
                                    + @tab
                                    + @tab
                                    + @tab
                                    + N'when '
                                    + @quotedColumnName
                                    + N' is not null'
                                    + @lineEnd
                                    + @tab
                                    + @tab
                                    + @tab
                                    + @tab
                                    + N' then N''/*'
                                    + @quotedColumnName
                                    + N'=*/'' + '
                                    + @valuePlaceholder
                                    + @lineEnd
                                    + @tab
                                    + @tab
                                    + @tab
                                    + N'else N''/*'
                                    + @quotedColumnName
                                    + N'=*/NULL'''
                                    + @lineEnd
                                    + @tab
                                    + @tab
                                    + N'  end'
                                    + @lineEnd;

        end;
        else begin;
            -- non-NULL direct value
            set @workingColumn =	@tab
                                    + @tab
                                    + N'+ N''/*'
                                    + @quotedColumnName
                                    + N'=*/'' + '
                                    + @valuePlaceholder
                                    + @lineEnd;

        end;

        -- Replace @valuePlaceholder with the appropriate value transformation
        -- Not all transformations are figured out yet...
        -- All string values are cast to NVARCHAR (rather than VARCHAR for ASCII strings)
        -- because the overall string that we are building is a unicode string. The leading
        -- quote on the value will appropriately type the value when the generated script
        -- is run.
        set	@workingColumn =	case @userTypeId
                                    when 34 -- image, presented as hexadecimal string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (@frontQuote + N'CAST(' + @quotedColumnName + N'as nvarchar(max))' + @endQuote))
                                    when 35 -- text, presented as hexadecimal string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (@frontQuote + N'CAST(' + @quotedColumnName + N'as nvarchar(max))' + @endQuote))
                                    when 36 -- uniqueidentifier, presented as hexadecimal string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (@frontQuote + N'CAST(' + @quotedColumnName + N' as nvarchar(36))' + @endQuote))
                                    when 40 -- date, presented as ASCII string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (N'N''CAST('' + ' + @frontQuote + N'CAST(' + @quotedColumnName + N' as nvarchar(10))' + @endQuote + N' + N'' AS date)'''))
                                    when 41 -- time, presented as ASCII string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (N'N''CAST('' + ' + @frontQuote + N'CAST(' + @quotedColumnName + N' as nvarchar(8))' + @endQuote + N' + N'' AS time)'''))
                                    when 42 -- datetime2, presented as ASCII string in ODBC Canonical style (may truncate long values?)
                                        then REPLACE(@workingColumn, @valuePlaceholder, (N'N''CAST('' + ' + @frontQuote + N' + CONVERT(nvarchar(27), ' + @quotedColumnName + N', 121)' + @endQuote + N' + N'' AS datetime2)'''))
                                    when 43 -- datetimeoffset, presented as ASCII string in ISO 8601 style
                                        then REPLACE(@workingColumn, @valuePlaceholder, (N'N''CAST('' + ' + @frontQuote + N' + CONVERT(nvarchar(34), ' + @quotedColumnName + N', 121)' + @endQuote + N' + N'' AS datetimeoffset)'''))
                                    when 48 -- tinyint, presented as ASCII string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (N'CAST(' + @quotedColumnName + N' as nvarchar(3))'))
                                    when 48 -- signed smallint, presented as ASCII string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (N'CAST(' + @quotedColumnName + N' as nvarchar(6))'))
                                    when 56 -- signed int, presented as ASCII string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (N'CAST(' + @quotedColumnName + N' as nvarchar(11))'))
                                    when 58 -- smalldatetime, presented as ASCII string in ODBC Canonical (no fractional seconds) style
                                        then REPLACE(@workingColumn, @valuePlaceholder, (N'N''CAST('' + ' + @frontQuote + N'CONVERT(nvarchar(19), ' + @quotedColumnName + N', 120)' + @endQuote + N' + N'' smalldatetime)'''))
                                     when 59 -- real, presented as ASCII string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (N'STR(' + @quotedColumnName + N', 56, 16)'))
                                     when 60 -- money, presented as ASCII string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (N'CAST(' + @quotedColumnName + N' as nvarchar(25))'))
                                    when 61 -- datetime, presented as ASCII string in ODBC Canonical style
                                        then REPLACE(@workingColumn, @valuePlaceholder, (N'N''CAST('' + ' + @frontQuote + N'CONVERT(nvarchar(23), ' + @quotedColumnName + N', 121)' + @endQuote + N' + N'' AS datetime)'''))
                                    when 62 -- float, presented as ASCII string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (N'STR(' + @quotedColumnName + N', 73, 16)'))
                                    --when 98 -- sql_variant
                                    when 99 -- ntext, presented as hexadecimal string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (@frontQuote + N'CAST(' + @quotedColumnName + N'as nvarchar(max))' + @endQuote))
                                    when 104 -- bit, presented as ASCII character
                                        then REPLACE(@workingColumn, @valuePlaceholder, (N'CAST(' + @quotedColumnName + N' as nchar(1))'))
                                    when 106 -- decimal, presented as ASCII string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (N'CAST(' + @quotedColumnName + N' as nvarchar(39))'))
                                    when 108 -- numeric, presented as ASCII string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (N'CAST(' + @quotedColumnName + N' as nvarchar(39))'))
                                    when 122 -- smallmoney, presented as ASCII string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (N'CAST(' + @quotedColumnName + N' as nvarchar(13))'))
                                    when 127 -- signed bigint, presented as ASCII string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (N'CAST(' + @quotedColumnName + N' as nvarchar(20))'))
                                    --when 128 -- hierarchyid
                                    --when 129 -- geometry
                                    --when 130 -- geography
                                    when 165 -- varbinary, presented as hexadecimal string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (@frontQuote + N'CAST(' + @quotedColumnName + N'as nvarchar(max))' + @endQuote))
                                    when 167 -- varchar, presented as ASCII string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (@frontQuote + N'REPLACE(' + @quotedColumnName + N', N'''''''', N'''''''''''')' + @endQuote))
                                    when 173 -- binary, presented as hexadecimal string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (@frontQuote + N'CAST(' + @quotedColumnName + N'as nvarchar(max))' + @endQuote))
                                    when 175 -- char, presented as ASCII string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (@frontQuote + N'REPLACE(' + @quotedColumnName + N', N'''''''', N'''''''''''')' + @endQuote))
                                    --when 189 -- timestamp
                                    when 231 -- nvarchar, presented as unicode string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (@nFrontQuote + N'REPLACE(' + @quotedColumnName + N', N'''''''', N'''''''''''')' + @endQuote))
                                    when 239 -- nchar, presented as unicode string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (@nFrontQuote + N'REPLACE(' + @quotedColumnName + N', N'''''''', N'''''''''''')' + @endQuote))
                                    --when 241 -- xml
                                    when 256 -- sysname, presented as unicode string
                                        then REPLACE(@workingColumn, @valuePlaceholder, (@nFrontQuote + N'REPLACE(' + @quotedColumnName + N', N'''''''', N'''''''''''')' + @endQuote))
                                    -- If we don't know the type or have a specific handler, toss it in a unicode string and hope for the best
                                    else REPLACE(@workingColumn, @valuePlaceholder, (@frontQuote + N'REPLACE(' + N'CAST(' + @quotedColumnName + N'as nvarchar(max))' + N', N'''''''', N'''''''''''''''')' + @endQuote))
                                end;

        -- Update the value generator statement
        set	@valueGeneratorStatement =	@valueGeneratorStatement
                                        + @workingColumn;

        -- Proceed to the next column
        fetch next from columnCursor
            into @columnId, @quotedColumnName, @userTypeId, @userTypeName, @isNullable, @columnNumber;

    end;

    close columnCursor;
    deallocate columnCursor;

    -- Add FROM clause to value generator
    set	@valueGeneratorStatement =	@valueGeneratorStatement
                                    + @tab
                                    + @tab
                                    + N' + N'' ),'''
                                    + @lineEnd
                                    + @tab
                                    + @tab
                                    + N'as '
                                    + QUOTENAME(@quotedSchemaQualifiedName, '[')
                                    + @lineEnd
                                    + N'from'
                                    + @tab
                                    + @quotedSchemaQualifiedName
                                    + N';'
                                    + @lineEnd;

    -- present value generator script
    select	@presentationStatement =	@presentationStatement
                                        + N', N'''
                                        + REPLACE(@valueGeneratorStatement, N'''', N'''''')
                                        + N''' as '
                                        + SCHEMA_NAME([schema_id])
                                        + N'_'
                                        + name
                                        + N'_valueGeneratorScript'
    from	sys.objects
    where	[object_id] = @objectId;

    --!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    --=======================================================================
    -- Present scripts
    --=======================================================================
    --!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    -- Terminate presentation statement
    select	@presentationStatement =	@presentationStatement
                                        + N';';

    begin try
        
        exec (@presentationStatement);

    end try

    begin catch
        
        select	N'ERROR attempting to present scripts. Script value dump:'	as ERROR,
                LEN(@presentationStatement)									as presentationStatementLength,
                @presentationStatement										as presentationStatement,
                LEN(@frontWrapper)											as frontWrapperLength,
                @frontWrapper												as frontWrapper,
                LEN(@backWrapper)											as backWrapperLength,
                @backWrapper												as backWrapper,
                LEN(@valueGeneratorStatement)								as valueGeneratorStatementLength,
                @valueGeneratorStatement									as valueGeneratorStatement,
                N'Error Info:'												as [ERROR INFO],
                ERROR_MESSAGE()												as errorMessage,
                ERROR_LINE()												as errorLine,
                ERROR_NUMBER()												as errorNumber,
                ERROR_STATE()												as errorState,
                ERROR_SEVERITY()											as errorSeverity;

    end catch;

    fetch next from tableCursor
    into @objectId, @quotedSchemaQualifiedName, @hasFkFlag, @addedForFkFlag;

end;

close tableCursor;
deallocate tableCursor;
