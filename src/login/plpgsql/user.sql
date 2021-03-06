-- user_add
-- user_delete
-- user_change_rights

SET search_path = login;

CREATE OR REPLACE FUNCTION _token_assert (
  prm_token integer, 
  prm_rights login.user_right[]) 
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  usr login."user";
BEGIN
  SELECT * INTO usr FROM login."user" WHERE 
    usr_token = prm_token AND
    (prm_rights ISNULL OR prm_rights <@ usr_rights); -- <@ 'is contained by'
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'insufficient_privilege';
  END IF;
END;
$$;
COMMENT ON FUNCTION _token_assert (prm_token integer, prm_rights login.user_right[])
IS '[INTERNAL] Assert that a token is valid.
Also assert that the user owns all the rights given in parameter.
If some assertion fails, an ''insufficient_privilege'' exception is raised.';

CREATE OR REPLACE FUNCTION _token_assert_any (
  prm_token integer, 
  prm_rights login.user_right[]) 
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  usr login."user";
BEGIN
  SELECT * INTO usr FROM login."user" WHERE 
    usr_token = prm_token AND
    (prm_rights ISNULL OR prm_rights && usr_rights); -- && 'overlap (have elements in common)'
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'insufficient_privilege';
  END IF;
END;
$$;
COMMENT ON FUNCTION _token_assert (prm_token integer, prm_rights login.user_right[])
IS '[INTERNAL] Assert that a token is valid.
Also assert that the user owns all the rights given in parameter.
If some assertion fails, an ''insufficient_privilege'' exception is raised.';

CREATE OR REPLACE FUNCTION login._token_assert_other_login(
  prm_token integer, 
  prm_login varchar)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM login."user" WHERE 
      usr_token = prm_token AND 
      usr_login = prm_login) THEN
    RAISE EXCEPTION USING ERRCODE = 'invalid_authorization_specification';
  END IF;
END;
$$;
COMMENT ON FUNCTION login._token_assert_other_login(prm_token integer, prm_login varchar) 
IS '[INTERNAL] Assert that the login and token are not associated.';

CREATE OR REPLACE FUNCTION _user_token_create (
  prm_login varchar) 
RETURNS varchar
  LANGUAGE plpgsql
  AS $$
DECLARE
	tok integer DEFAULT NULL;
	found BOOLEAN DEFAULT true;
BEGIN
  WHILE found LOOP
    tok = (RANDOM()*1000000000)::int;
    IF NOT EXISTS (SELECT 1 FROM login."user" WHERE usr_token = tok) THEN
      found = false;
    END IF;
  END LOOP;
  UPDATE login."user" SET 
    usr_token = tok, 
    usr_token_creation_date = CURRENT_TIMESTAMP 
    WHERE usr_login = prm_login;
  RETURN tok;
END;
$$;
COMMENT ON FUNCTION login._user_token_create (prm_login varchar) IS 
'[INTERNAL] Create a new token for the given user';


DROP FUNCTION IF EXISTS user_login(
  prm_login character varying, 
  prm_pwd character varying, 
  prm_rights login.user_right[]);
DROP TYPE IF EXISTS user_login;
CREATE TYPE user_login AS (
  usr_token integer,
  usr_temp_pwd boolean,
  usr_rights login.user_right[],
  par_id integer,
  ugr_id integer,
  par_firstname text,
  par_lastname text,
  usr_previous_connection_date timestamp with time zone,
  usr_previous_connection_ip inet
);
COMMENT ON TYPE user_login IS 'Type returned by user_login function';
COMMENT ON COLUMN user_login.usr_token IS 'Token to use for other functions';
COMMENT ON COLUMN user_login.usr_temp_pwd IS 'True if the password is temporary';
COMMENT ON COLUMN user_login.usr_rights IS 'List of rights owned by the user.';
COMMENT ON COLUMN user_login.par_id IS 'Participant linked with this user.';

CREATE OR REPLACE FUNCTION user_login(
  prm_login character varying, 
  prm_pwd character varying, 
  prm_rights login.user_right[],
  prm_connection_ip inet) 
RETURNS user_login
  LANGUAGE plpgsql
  AS $$
DECLARE
  row login.user_login;
  usr varchar;
  tok integer DEFAULT NULL;
BEGIN
  SELECT usr_login INTO usr FROM login."user"
    WHERE usr_login = prm_login AND 
    pgcrypto.crypt (prm_pwd, usr_salt) = usr_salt AND
    (prm_rights ISNULL OR prm_rights <@ usr_rights); -- <@: 'is contained by'
  IF NOT FOUND THEN 
    RAISE EXCEPTION USING ERRCODE = 'invalid_authorization_specification';
  END IF;
  SELECT usr_token INTO tok FROM login."user" WHERE usr_token NOTNULL AND usr_login = usr;
  IF NOT FOUND THEN
    SELECT * INTO tok FROM login._user_token_create (usr);
  END IF;
  UPDATE login."user" SET 
    usr_last_connection_date = CURRENT_TIMESTAMP, 
    usr_last_connection_ip = prm_connection_ip 
    WHERE usr_login = usr;
  SELECT DISTINCT 
    tok, (usr_pwd NOTNULL), usr_rights, par_id, ugr_id, 
    par_firstname, par_lastname,
    usr_last_connection_date, usr_last_connection_ip
   INTO row 
    FROM login."user"
    LEFT JOIN organ.participant USING(par_id)
    WHERE usr_login = usr;
  RETURN row;
END;
$$;
COMMENT ON FUNCTION login.user_login(
  character varying, 
  character varying, 
 prm_rights login.user_right[],
  prm_connection_ip inet) IS 
'Authenticate a user from its login and password.
If prm_rights is not null, also verify that user owns all the specified rights.
If authorization is ok, returns:
 - usr_token: a new token to be used for the following operations
 - usr_temp_pwd: true if the user is using a temporary password
 - usr_rights: the list of rights owned by the user.
If authorization fails, an exception is raised with code invalid_authorization_specification
';

CREATE OR REPLACE FUNCTION user_login_json(
  prm_login character varying, 
  prm_pwd character varying, 
  prm_rights login.user_right[],
  prm_connection_ip inet,
  req json) 
RETURNS json
  LANGUAGE plpgsql
  AS $$
DECLARE
  ret json;
  usr varchar;
  tok integer DEFAULT NULL;
BEGIN
  SELECT usr_login INTO usr FROM login."user"
    WHERE usr_login = prm_login AND 
    pgcrypto.crypt (prm_pwd, usr_salt) = usr_salt AND
    (prm_rights ISNULL OR prm_rights <@ usr_rights); -- <@: 'is contained by'
  IF NOT FOUND THEN 
    RAISE EXCEPTION USING ERRCODE = 'invalid_authorization_specification';
  END IF;
  SELECT usr_token INTO tok FROM login."user" WHERE usr_token NOTNULL AND usr_login = usr;
  IF NOT FOUND THEN
    SELECT * INTO tok FROM login._user_token_create (usr);
  END IF;
  SELECT row_to_json(d) INTO ret 
    FROM (SELECT
      CASE WHEN (req->>'usr_token') IS NULL THEN NULL ELSE usr_token END AS usr_token,
      CASE WHEN (req->>'usr_temp_pwd') IS NULL THEN NULL ELSE (usr_pwd NOTNULL) END AS usr_temp_pwd,
      CASE WHEN (req->>'usr_rights') IS NULL THEN NULL ELSE usr_rights END AS usr_rights,
      CASE WHEN (req->>'usr_previous_connection_date') IS NULL THEN NULL ELSE usr_last_connection_date END AS usr_previous_connection_date,
      CASE WHEN (req->>'usr_previous_connection_ip') IS NULL THEN NULL ELSE usr_last_connection_ip END AS usr_previous_connection_ip,
      CASE WHEN (req->>'usergroup') IS NULL THEN NULL 
           WHEN ugr_id IS NULL THEN NULL
	   ELSE login.usergroup_json(tok, ugr_id, req->'usergroup') END AS usergroup,
      CASE WHEN (req->>'participant') IS NULL THEN NULL 
           WHEN par_id IS NULL THEN NULL
	   ELSE organ.participant_json(tok, par_id, req->'participant') END AS participant
      FROM login."user"
      LEFT JOIN organ.participant USING(par_id)
      WHERE usr_login = usr) d;
  -- update after getting values so we can return previous connection infos
  UPDATE login."user" SET 
    usr_last_connection_date = CURRENT_TIMESTAMP, 
    usr_last_connection_ip = prm_connection_ip 
    WHERE usr_login = usr;

  RETURN ret;
END;
$$;
COMMENT ON FUNCTION login.user_login_json(
  character varying, 
  character varying, 
  prm_rights login.user_right[], 
  prm_connection_ip inet,  
  req json) IS 
'Authenticate a user from its login and password.
If prm_rights is not null, also verify that user owns all the specified rights.
If authorization is ok, returns:
 - usr_token: a new token to be used for the following operations
 - usr_temp_pwd: true if the user is using a temporary password
 - usr_rights: the list of rights owned by the user.
If authorization fails, an exception is raised with code invalid_authorization_specification
';

CREATE OR REPLACE FUNCTION user_logout (
  prm_token integer)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  UPDATE login."user" SET usr_token = NULL, usr_token_creation_date = NULL
    WHERE "user".usr_token = prm_token;
END;
$$;
COMMENT ON FUNCTION login.user_logout(integer) IS 
'Disconnect the user. The user token will not be usable anymore after this call.';

CREATE DOMAIN login.valid_password 
  AS text
  CHECK(char_length(VALUE) >= 8 
        AND 2 < char_length(COALESCE(substring(VALUE from '[^a-zA-Z0-9]'), '')
                           || COALESCE(substring(VALUE from  '[0-9]'), '')
                           || COALESCE(substring(VALUE from '[A-Z]'), '')
                           || COALESCE(substring(VALUE from '[a-z]'), '')));

CREATE OR REPLACE FUNCTION user_change_password(
  prm_token integer, 
  prm_password text)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE 
  pwd login.valid_password = '123456aA';
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  pwd = prm_password; -- asserts that prm_password is in domain
  UPDATE login."user" SET usr_pwd = NULL, usr_salt = pgcrypto.crypt (prm_password, pgcrypto.gen_salt('bf', 8)) 
    WHERE usr_token = prm_token;
END;
$$;
COMMENT ON FUNCTION user_change_password(prm_token integer, prm_password text) IS
'Change the password of the current user.';

CREATE OR REPLACE FUNCTION user_regenerate_password(
  prm_token integer, 
  prm_login varchar)
RETURNS varchar
LANGUAGE plpgsql
AS $$
DECLARE
  newpwd varchar;
BEGIN
  PERFORM login._token_assert(prm_token, '{users}');
  PERFORM login._token_assert_other_login(prm_token, prm_login);
  newpwd = LPAD((random()*1000000)::int::varchar, 6, '0');
  UPDATE login."user" SET 
    usr_salt = pgcrypto.crypt (newpwd, pgcrypto.gen_salt('bf', 8)), 
    usr_pwd = newpwd
    WHERE usr_login = prm_login;
  RETURN newpwd;
END;
$$;
COMMENT ON FUNCTION user_regenerate_password(prm_token integer, prm_login varchar) IS
'Regenerate a temporary password for the user given in parameter.
The user given in parameter cannot be the current user.';

CREATE OR REPLACE FUNCTION user_add(
  prm_token integer, 
  prm_login text, 
  prm_rights login.user_right[], 
  prm_par_id integer,
  prm_ugr_id integer) 
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM login._token_assert (prm_token, '{users}');
  INSERT INTO login."user" (usr_login, usr_rights, par_id, ugr_id) VALUES (prm_login, prm_rights, prm_par_id, prm_ugr_id);
  PERFORM login.user_regenerate_password(prm_token, prm_login);
END;
$$;
COMMENT ON FUNCTION user_add(prm_token integer, prm_login text, prm_rights login.user_right[], prm_par_id integer, prm_ugr_id integer) 
IS 'Create a new user with the specified rights, and link him to a participant. If prm_par_id is null,
this user will have access to all patients. A new temporary password is generated.';

DROP FUNCTION IF EXISTS login.user_info(prm_token integer, prm_login text);
DROP TYPE IF EXISTS login.user_info;
CREATE TYPE login.user_info AS (
  usr_login text,
  usr_rights login.user_right[],
  par_id integer,
  ugr_id integer,
  par_firstname text,
  par_lastname text
);

CREATE FUNCTION login.user_info(
  prm_token integer, 
  prm_login text)
RETURNS login.user_info
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  ret login.user_info;
BEGIN
  PERFORM login._token_assert (prm_token, '{users}');
  SELECT usr_login, usr_rights, par_id, ugr_id, par_firstname, par_lastname INTO ret 
    FROM login."user" 
    LEFT JOIN organ.participant USING(par_id)
    WHERE usr_login = prm_login;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;
  RETURN ret;
END;
$$;
COMMENT ON FUNCTION login.user_info(prm_token integer, prm_login text) IS 'Return information about a user';

CREATE OR REPLACE FUNCTION login.user_get_temporary_pwd(prm_token integer, prm_login text)
RETURNS text
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  ret text DEFAULT NULL;
BEGIN
  PERFORM login._token_assert(prm_token, '{users}');
  SELECT usr_pwd INTO ret
    FROM login.user
    WHERE usr_login = prm_login;
  RETURN ret;
END;
$$;
COMMENT ON FUNCTION login.user_get_temporary_pwd(prm_token integer, prm_login text) IS 'Return the temporary password of an user if there is one';

CREATE OR REPLACE FUNCTION login.user_update(prm_token integer, prm_login text, prm_par_id integer, prm_ugr_id integer, prm_rights login.user_right[])
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, '{users}');
  UPDATE login.user SET par_id = prm_par_id, ugr_id = prm_ugr_id, usr_rights = prm_rights WHERE usr_login = prm_login;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;
COMMENT ON FUNCTION login.user_update(prm_token integer, prm_login text, prm_par_id integer, prm_ugr_id integer, prm_rights login.user_right[]) IS 'Update an user informations';

CREATE OR REPLACE FUNCTION login.user_participant_set(
  prm_token integer, 
  prm_login text, 
  prm_par_id integer)
RETURNS void
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  PERFORM login._token_assert (prm_token, '{users}');
  UPDATE login.user SET par_id = prm_par_id WHERE usr_login = prm_login;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;
COMMENT ON FUNCTION login.user_participant_set(prm_token integer, prm_login text, prm_par_id integer) 
IS 'Link a participant to a user';

CREATE OR REPLACE FUNCTION login.user_usergroup_set(
  prm_token integer, 
  prm_login text, 
  prm_ugr_id integer)
RETURNS void
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  PERFORM login._token_assert (prm_token, '{users}');
  UPDATE login.user SET ugr_id = prm_ugr_id WHERE usr_login = prm_login;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;
COMMENT ON FUNCTION login.user_usergroup_set(prm_token integer, prm_login text, prm_ugr_id integer) 
IS 'Place a user in a user group';

DROP FUNCTION IF EXISTS login.user_list(prm_token integer);
DROP TYPE IF EXISTS login.user_details;
CREATE TYPE login.user_details AS (
  usr_login text,
  usr_rights login.user_right[],
  par_id integer,
  par_firstname text,
  par_lastname text,
  ugr_id integer,
  ugr_name text
);

CREATE FUNCTION login.user_list(prm_token integer, prm_ugr_id integer)
RETURNS SETOF login.user_details
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, '{users}');
  RETURN QUERY 
    SELECT 
      usr_login, usr_rights,
      par_id, par_firstname, par_lastname,
      ugr_id, ugr_name
      FROM login.user 
      LEFT JOIN organ.participant USING(par_id)
      LEFT JOIN login.usergroup USING(ugr_id)
      WHERE
      (
	CASE
	  WHEN prm_ugr_id = -1 THEN login.user.ugr_id IS NULL
	  WHEN prm_ugr_id ISNULL THEN prm_ugr_id ISNULL
	  ELSE prm_ugr_id = usergroup.ugr_id
	END
      )
      ORDER BY usr_login;
END;
$$;
COMMENT ON FUNCTION login.user_list(prm_token integer, prm_ugr_id integer) IS 'Return the list of users.
if prm_ugr_id is not null, filter by usergroup.';

CREATE OR REPLACE FUNCTION login.user_delete(prm_token integer, prm_login text)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, '{users}');
  DELETE FROM login.user WHERE usr_login = prm_login;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;
END;
$$;
COMMENT ON FUNCTION login.user_delete(prm_token integer, prm_login text) IS 'Delete an user';

DROP TYPE IF EXISTS login.user_usergroup_type;
CREATE TYPE login.user_usergroup_type AS (
  ugr_name text,
  usr_login text[]
);

CREATE OR REPLACE FUNCTION login.user_list_demo()
RETURNS	SETOF login.user_usergroup_type
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  -- TODO : check if demo state or not
  RETURN QUERY
    SELECT ugr_name, array_agg(usr_login) as usr_login
    FROM login.usergroup
    RIGHT JOIN login.user USING(ugr_id)
    GROUP BY ugr_name
    ORDER BY ugr_name;
END;
$$;
COMMENT ON FUNCTION login.user_list_demo() IS 'Return a list of users login to show on login page (ONLY FOR DEMO)';

CREATE OR REPLACE FUNCTION login.user_right_list()
RETURNS SETOF login.user_right
LANGUAGE plpgsql
STABLE 
AS $$
BEGIN
 RETURN QUERY SELECT unnest(enum_range(null::login.user_right));
END;
$$;
COMMENT ON FUNCTION login.user_right_list() IS 'Returns the list of user rights';

