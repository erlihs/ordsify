# ORDSify

**ORDSify** is an Oracle Database PLSQL procedure for exposing PLSQL Package as Oracle Rest Data Services (ORDS).   

## Description

**ORDSify** is an Oracle Database PLSQL procedure for exposing PLSQL Package as Oracle Rest Data Services (ORDS).  It uses certain naming conventions to turn procedures within package into REST web services, anonymous or protected with OAuth access token.

## Getting Started

### Dependencies

* Oracle Database 12c or higher
* ORDS 17.4 or higher

### Installation

Modify parameters as needed

```sql
CREATE OR REPLACE PROCEDURE ordsify (
    p_package_name VARCHAR2 DEFAULT NULL, -- package name which needs to be converted, NULL - all packages
    p_version_name VARCHAR2 DEFAULT 'v1', -- api version - will appear in URL
    p_oauth_client_name VARCHAR2 DEFAULT '<OAuth client name>',  -- OAuth client name, needed for services that require token authentication
    p_oauth_client_description VARCHAR2 DEFAULT '<OAuth client description>', -- OAuth client description
    p_oauth_client_email VARCHAR2 DEFAULT '<OAuth client email>' -- OAuth client email
)
```

### Executing program

Add at the end of your package setup script or execute separately:

```
exec ordsify;
/
```

## Naming conventions

Procedure is converted to service if it's name contains underscore separated prefix *get*, *post*, *put* or *deleted*. The prefix will become method for web service representing that procedure.

Input parameters must contain underscore separated prefix *p_*.

Output data are returned as a reference to a cursor or single value (e.g. VARCHAR2) and must have an underscore separated prefix *r_*. One procedure can have multiple outputs.

If procedure requires authentication, it's name must contain underscore separated postfix *token*.

Check examples at **pck_example.sql** 

## Authors

Jānis Erlihs   
https://twitter.com/erlihs

## Version History

* 0.1
    * Initial Release

## License

This project is licensed under the [MIT License](https://opensource.org/license/mit/) 

## Acknowledgments

Inspiration, code snippets, etc.
* [Oracle Base](https://oracle-base.com/)
* [That Jeff Smith](https://www.thatjeffsmith.com/)
