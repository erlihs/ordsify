CREATE OR REPLACE PROCEDURE ordsify (
    p_package_name VARCHAR2 DEFAULT NULL,
    p_version_name VARCHAR2 DEFAULT 'v1',
    p_oauth_client_name VARCHAR2 DEFAULT '<OAuth client name>',
    p_oauth_client_description VARCHAR2 DEFAULT '<OAuth client description>',
    p_oauth_client_email VARCHAR2 DEFAULT '<Oauth client email>'
) AS
    v_schema_name VARCHAR2(30 CHAR);
    v_creditentials VARCHAR2(2000 CHAR);
    
    v_module VARCHAR2(30 CHAR);
    v_role VARCHAR2(30 CHAR);
    v_privilege VARCHAR2(30 CHAR);
    
    v_method VARCHAR2(30 CHAR); 
    v_pattern VARCHAR2(2000 CHAR);
    v_params VARCHAR2(2000 CHAR);
    v_argument VARCHAR2(30 CHAR);
    v_param_type VARCHAR2(30 CHAR);
    v_comment VARCHAR2(2000 CHAR);

    v_dummy owa.vc_arr;
    v_patterns owa.vc_arr;
    v_roles owa.vc_arr;
    v_modules owa.vc_arr; 
    v_privileges  t_ords_vchar_tab  := t_ords_vchar_tab();
    
    PROCEDURE log(
        p VARCHAR2
    ) AS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(p);
    END;

    FUNCTION get_comment(
        p_package VARCHAR2,
        p_procedure VARCHAR2,
        p_parameter VARCHAR2
    ) RETURN VARCHAR2
    AS
        v_comment VARCHAR2(2000 CHAR);
    BEGIN

        WITH package AS (
            SELECT 
                line,
                text
            FROM user_source
            WHERE type = 'PACKAGE'
            AND name = UPPER(TRIM(p_package))
        ), firstline AS (
            SELECT MIN(line) AS firstline
            FROM package
            WHERE UPPER(text) LIKE '%' || UPPER(TRIM(p_procedure)) ||'%' 
        ), lastline AS (
            SELECT MIN(line) AS lastline
            FROM package
            WHERE line > (SELECT firstline FROM firstline)
            AND line = (
                SELECT MIN(line) AS lastline
                FROM package
                WHERE line > (SELECT firstline FROM firstline)
                AND UPPER(text) LIKE '%);%'
            )
        )
        SELECT CASE WHEN text LIKE  '%--%'  THEN TRIM(SUBSTR(text, INSTR(text, '-') + 2))  ELSE NULL END
        INTO v_comment
        FROM package    
        WHERE (p_parameter IS NULL AND line = (SELECT firstline  FROM firstline))
        OR (
            p_parameter IS NOT NULL 
            AND line >= (SELECT firstline  FROM firstline)
            AND line <= (SELECT lastline FROM lastline)
            AND UPPER(text) like '%' || UPPER(TRIM(p_parameter)) || '%'
        )
        ;
        
        v_comment := REPLACE(v_comment,CHR(10),'');
        v_comment := REPLACE(v_comment,CHR(13),'');

        RETURN v_comment;

    EXCEPTION
        WHEN TOO_MANY_ROWS THEN
            RETURN NULL;

    END;

BEGIN

    log('Begin setup of ORDS services');
    
    SELECT LOWER(sys_context( 'userenv', 'current_schema' )) 
    INTO v_schema_name 
    FROM dual;
    
    log('Schema: ' || v_schema_name);

    -- drop existing

    ORDS.DROP_REST_FOR_SCHEMA(UPPER(v_schema_name));

    COMMIT;

    -- Enable schema 

    ORDS.enable_schema(
        p_enabled             => TRUE,
        p_schema              => v_schema_name,
        p_url_mapping_type    => 'BASE_PATH',
        p_url_mapping_pattern => v_schema_name,
        p_auto_rest_auth      => FALSE
    );

    COMMIT;
    
    log('ORDS enabled for schema');
    
    -- OAuth

    OAUTH.DELETE_CLIENT(
        p_oauth_client_name
    );

    OAUTH.CREATE_CLIENT(
        p_name => p_oauth_client_name,
        p_description => p_oauth_client_description,
        p_grant_type => 'client_credentials',
        p_owner => v_schema_name,
        p_privilege_names => NULL, -- add later
        p_support_email => p_oauth_client_email
    );

    COMMIT;
    
    log('OAUTH client created: ' || p_oauth_client_name); -- select client_id,client_secret from user_ords_clients;

-- modules
   
    FOR m IN (
        SELECT object_name
        FROM all_objects
        WHERE owner = UPPER(v_schema_name)
        AND object_type = 'PACKAGE'
        AND (
            (p_package_name IS NULL)
            OR 
            (UPPER(p_package_name) = object_name)
        )
    )
    LOOP
    
        v_module := LOWER(REPLACE(REPLACE(m.OBJECT_NAME,'PCK_',''),'_','-')) || '-' || p_version_name; -- pck_app => app-v1
        
        log('');
        log('Creating module: ' || v_module);
        
        v_comment := get_comment(m.OBJECT_NAME, NULL, NULL);
        
        ORDS.define_module(
            p_module_name    => v_module,
            p_base_path      => v_module || '/',
            p_items_per_page => 0,
            p_comments       => v_comment
        );        

        FOR p IN (
            SELECT o.PROCEDURE_NAME
            FROM all_procedures o
            WHERE o.OBJECT_NAME = m.OBJECT_NAME
            AND o.PROCEDURE_NAME IS NOT NULL
            AND o.OWNER = UPPER(v_schema_name)
            ORDER BY o.SUBPROGRAM_ID
        )    
        LOOP

            v_method :=  CASE 
                WHEN p.PROCEDURE_NAME LIKE 'POST_%' THEN 'POST' 
                WHEN p.PROCEDURE_NAME LIKE 'PUT_%' THEN 'PUT' 
                WHEN p.PROCEDURE_NAME LIKE 'DELETE_%' THEN 'DELETE' 
                WHEN p.PROCEDURE_NAME LIKE 'GET_%' THEN 'GET' 
                ELSE NULL
                END;
            
            IF v_method IS NOT NULL THEN
        
                v_params := '';
                v_pattern := '';
    
                FOR a IN (
                    SELECT ARGUMENT_NAME, DEFAULTED, IN_OUT
                    FROM ALL_ARGUMENTS
                    WHERE PACKAGE_NAME = m.OBJECT_NAME
                    AND OBJECT_NAME = p.PROCEDURE_NAME
                    AND OWNER  = UPPER(v_schema_name)
                    ORDER BY POSITION
                )
                LOOP 
                
                    v_argument := CASE 
                        WHEN SUBSTR(a.ARGUMENT_NAME,1,2) IN ('P_', 'R_') THEN SUBSTR(LOWER(a.ARGUMENT_NAME),3)
                        ELSE LOWER(a.ARGUMENT_NAME) END;
                
                    v_params := v_params || LOWER(a.ARGUMENT_NAME) || ' => :' || v_argument || ',';
    
                    IF a.DEFAULTED = 'N' THEN
    
                        IF a.IN_OUT = 'IN' THEN
                            v_pattern := v_pattern || ':' || v_argument || '/';
                        END IF;
    
                    END IF;
    
                END LOOP;
    
                v_params := SUBSTR(v_params,1,LENGTH(v_params) - 1);  
                IF (LENGTH(v_params) > 0) THEN v_params := '(' || v_params || ')'; END IF;
                v_pattern := SUBSTR(v_pattern,1,LENGTH(v_pattern) - 1);  
    
                v_pattern := LOWER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(p.PROCEDURE_NAME,'POST_'),'GET_'),'PUT_'),'DELETE_'),'_TOKEN')) || '/' || CASE WHEN v_method = 'GET' THEN v_pattern ELSE NULL END;

                v_comment := NULL;
                --v_comment := get_comment(m.OBJECT_NAME, p.PROCEDURE_NAME, NULL); 

                ORDS.define_template(
                    p_module_name => v_module,
                    p_pattern => v_pattern,
                    p_comments => v_comment
                );
                
                COMMIT;

                ORDS.define_handler(
                    p_module_name    => v_module,
                    p_pattern        => v_pattern,
                    p_method         => v_method,
                    p_source_type    => ORDS.source_type_plsql,
                    p_source         => 'BEGIN ' || LOWER(m.OBJECT_NAME) || '.' || LOWER(p.PROCEDURE_NAME) || '' || v_params || '; END;',
                    p_items_per_page => 0,
                    p_comments => v_comment
                );
                
                COMMIT;
                
                FOR a IN (
                    SELECT ARGUMENT_NAME, DEFAULTED, IN_OUT, DATA_TYPE
                    FROM ALL_ARGUMENTS
                    WHERE PACKAGE_NAME = m.OBJECT_NAME
                    AND OBJECT_NAME = p.PROCEDURE_NAME
                    AND OWNER  = UPPER(v_schema_name)
                    ORDER BY POSITION
                )
                LOOP                 

                    v_argument := CASE 
                        WHEN SUBSTR(a.ARGUMENT_NAME,1,2) IN ('P_', 'R_') THEN SUBSTR(LOWER(a.ARGUMENT_NAME),3)
                        ELSE LOWER(a.ARGUMENT_NAME) END;
                    
                    -- https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/18.3/aelig/ords-database-type-mappings.html#GUID-4F7FA58A-1C29-4B7E-819F-21DB4B68FFE1
                    v_param_type := CASE a.DATA_TYPE -- The native type of the parameter. Valid values: STRING, INT, DOUBLE, BOOLEAN, LONG, TIMESTAMP
                        WHEN 'REF CURSOR' THEN 'RESULTSET'
                        WHEN 'BINARY_INTEGER' THEN 'INT'
                        ELSE 'STRING'
                        END;

                    -- v_comment := get_comment(m.OBJECT_NAME, p.PROCEDURE_NAME, a.ARGUMENT_NAME); 
                    v_comment := NULL;

                    ORDS.define_parameter(
                        p_module_name        => v_module,
                        p_pattern            => v_pattern,
                        p_method             => v_method,
                        p_name               => v_argument,
                        p_bind_variable_name => v_argument,                        
                        p_source_type        => CASE a.IN_OUT WHEN 'OUT' THEN 'RESPONSE' ELSE 'HEADER' END,
                        p_param_type         => v_param_type,
                        p_access_method      => a.IN_OUT,
                        p_comments           => v_comment
                    );

                    COMMIT;

                END LOOP;
                
                IF (p.PROCEDURE_NAME LIKE '%_TOKEN') THEN

                    v_patterns(v_patterns.count + 1) := '/' || v_module || '/' || LOWER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(p.PROCEDURE_NAME,'POST_'),'GET_'),'PUT_'),'DELETE_'),'_TOKEN')) || '/*';

                    log(CHR(9) || 'Creating service: ' || v_method || ' ' || v_pattern || ' with OAUTH authorization');  

                ELSE 

                    log(CHR(9) || 'Creating service: ' || v_method || ' ' || v_pattern);  

                END IF;   
            
            END IF;
        
        END LOOP;

        IF  (v_patterns.count > 0) THEN
    
            v_role := LOWER(REPLACE(m.OBJECT_NAME,'PCK_','')) || '_role'; -- pck_app => app_role

            ORDS.create_role(
                p_role_name => v_role
            );

            COMMIT;

            v_privilege := LOWER(REPLACE(m.OBJECT_NAME,'PCK_','')) || '_priv'; -- pck_app => app_priv
            v_privileges.EXTEND;
            v_privileges(v_privileges.LAST) := v_privilege;

            v_modules(1) := v_module;
            v_roles(1) := v_role;
            
            ORDS.define_privilege(
                p_privilege_name  => v_privilege,
                p_roles => v_roles,
                p_patterns => v_patterns,
                --p_modules => v_modules,
                p_label => 'Service access',
                p_description => 'Provide access to ' || p_oauth_client_name,
                p_comments => 'Privilege comments..'
            ); 
            
            v_patterns := v_dummy;
            
            COMMIT;
    
            OAUTH.grant_client_role(
                p_client_name => p_oauth_client_name,
                p_role_name   => v_role
            );

            COMMIT;
            
            log('');
            log(CHR(9) || 'Granted privileges to: ' || v_role); 
    
        END IF;        

    END LOOP;
    
    -- done
    
    OAUTH.update_client( 
        p_name => p_oauth_client_name,
        p_privilege_names => v_privileges
    );

    COMMIT;
    SELECT client_id || ':' || client_secret AS creditentials 
    INTO v_creditentials
    FROM user_ords_clients 
    WHERE name = p_oauth_client_name;

    log('');
    log('Success!');  
    log(CHR(9) || 'OAuth client creditentials: ' || v_creditentials); 
    
END;
/
