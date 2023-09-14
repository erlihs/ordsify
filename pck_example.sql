-- Script creates package for * web application
-- Deploy procedure ordsify on the same schema as this package

SET SERVEROUTPUT ON;
/

ALTER SESSION SET CURRENT_SCHEMA = dzenis;
/

CREATE OR REPLACE PACKAGE pck_example AS -- Package provides routines for * Web Application

    g_oauth_client_name VARCHAR2(200 CHAR) := '<OAuth client name>';
    g_oauth_client_url VARCHAR2(200 CHAR) := 'https://<ORDS host name>/ords/<schema name>/oauth/token';

    /*ANONYMOUS*/

    PROCEDURE get_version( -- Procedure returns version data
        r_version OUT VARCHAR2
    );
    
    PROCEDURE post_login ( -- Procedure authenticates user and returns token
        p_username APP_USERS.USERNAME%TYPE, -- User name (e-mail address)
        p_password APP_USERS.PASSWORD%TYPE, -- Password
        r_token OUT VARCHAR2, -- Token
        r_error OUT VARCHAR2 --  Error (NULL if success)
    );
    
    /* PROTECTED */

    PROCEDURE get_context_token( -- Procedure returns application context for authentication  user
        r_params OUT SYS_REFCURSOR, -- Sample data 1
        r_data OUT SYS_REFCURSOR, -- Sample data 2
        r_error OUT VARCHAR2 -- Error (NULL if sucess)
    );

END;
/

CREATE OR REPLACE PACKAGE BODY pck_example AS

    /*ANONYMOUS*/

    PROCEDURE get_version(
        r_version OUT VARCHAR2      
    ) AS
    BEGIN
    
        SELECT '1.0'
        INTO r_version FROM dual;
        
    END;    
    
    PROCEDURE post_login (
        p_username APP_USERS.USERNAME%TYPE,
        p_password APP_USERS.PASSWORD%TYPE,
        r_token OUT VARCHAR2,
        r_error OUT VARCHAR2
    ) AS
        v_oauth_token_url VARCHAR2(2000 CHAR);
        v_oauth_client_name VARCHAR2(2000 CHAR); 
        v_oauth_client_id VARCHAR2(2000 CHAR);
        v_oauth_client_secret VARCHAR2(2000 CHAR);
        v_token APP_USERS.TOKEN%TYPE;
    BEGIN

        IF NOT ((p_username = 'demo') AND (p_password = 'demo')) THEN 

            r_error := 'Wrong user name or passoword';

        ELSE -- success
        

            SELECT client_id, client_secret
            INTO v_oauth_client_id, v_oauth_client_secret
            FROM user_ords_clients
            WHERE name = g_oauth_client_name;

            APEX_WEB_SERVICE.oauth_authenticate(
                p_token_url     => g_oauth_client_url,
                p_client_id     => v_oauth_client_id,
                p_client_secret => v_oauth_client_secret
            );

            r_token := APEX_WEB_SERVICE.OAUTH_GET_LAST_TOKEN;

        END IF;

    END;    
    
    PROCEDURE get_context_token( 
        r_params OUT SYS_REFCURSOR, 
        r_data OUT SYS_REFCURSOR, 
        r_error OUT VARCHAR2 
    ) AS
    BEGIN

        OPEN r_params FOR
        SELECT 'foo' AS "key", 1 AS "value" FROM dual
        UNION ALL 
        SELECT 'bar' AS "key", 0 AS "value" FROM dual
        ;

        OPEN r_data FOR
        SELECT 1 AS "data", 'foobar' AS "more_data" FROM dual
        ;

    END;

END;
/

exec ordsify;
/

