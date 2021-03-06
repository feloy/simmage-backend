SET search_path = login;

CREATE OR REPLACE FUNCTION login.usergroup_add(
  prm_token integer, 
  prm_name text,
  prm_ugr_rights login.usergroup_right[],
  prm_statuses organ.dossier_status_value[])
RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  ret integer;
BEGIN
  PERFORM login._token_assert(prm_token, '{users}');
  INSERT INTO login.usergroup (ugr_name, ugr_rights, ugr_statuses) VALUES (prm_name, prm_ugr_rights, prm_statuses)
    RETURNING ugr_id INTO ret;
  RETURN ret;
END;
$$;
COMMENT ON FUNCTION login.usergroup_add(prm_token integer, prm_name text, prm_ugr_rights login.usergroup_right[], prm_statuses organ.dossier_status_value[]) IS 'Add a new user group';

CREATE OR REPLACE FUNCTION login.usergroup_rename(prm_token integer, prm_ugr_id integer, prm_name text)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, '{users}');
  UPDATE login.usergroup SET ugr_name = prm_name WHERE ugr_id = prm_ugr_id;
END;
$$;
COMMENT ON FUNCTION login.usergroup_rename(prm_token integer, prm_ugr_id integer, prm_name text) IS 'Rename an usergroup';

CREATE OR REPLACE FUNCTION login.usergroup_update(prm_token integer, prm_ugr_id integer, prm_name text, prm_ugr_rights login.usergroup_right[], prm_statuses organ.dossier_status_value[])
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, '{users}');
  UPDATE login.usergroup SET ugr_name = prm_name, ugr_statuses = prm_statuses, ugr_rights = prm_ugr_rights WHERE ugr_id = prm_ugr_id;
END;
$$;
COMMENT ON FUNCTION login.usergroup_update(prm_token integer, prm_ugr_id integer, prm_name text, prm_ugr_rights login.usergroup_right[], prm_statuses organ.dossier_status_value[])
IS 'Update an usergroup name and/or its authorized dossier statuses values';

CREATE OR REPLACE FUNCTION login.usergroup_get(prm_token integer, prm_ugr_id integer)
RETURNS login.usergroup
LANGUAGE plpgsql
STABLE
AS $$
DECLARE 
  ugr login.usergroup;
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  SELECT * INTO ugr FROM login.usergroup WHERE ugr_id = prm_ugr_id;
  RETURN ugr;
END;
$$;
COMMENT ON FUNCTION login.usergroup_get(prm_token integer, prm_ugr_id integer) IS 'Return an usergroup';

CREATE OR REPLACE FUNCTION login.usergroup_list(
  prm_token integer)
RETURNS SETOF login.usergroup
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  RETURN QUERY SELECT * FROM login.usergroup ORDER BY ugr_name;
END;
$$;
COMMENT ON FUNCTION login.usergroup_list(prm_token integer) IS 'List the users groups';

CREATE OR REPLACE FUNCTION login.usergroup_set_portals(
  prm_token integer, 
  prm_ugr_id integer, 
  prm_por_ids integer[])
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  t integer;
BEGIN
  PERFORM login._token_assert(prm_token, '{users}');
  -- Raise an exception if entity does not exist
  IF NOT EXISTS (SELECT 1 FROM login.usergroup WHERE ugr_id = prm_ugr_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;
  -- If list is NULL, remove all relations
  IF prm_por_ids ISNULL THEN
    DELETE FROM login.usergroup_portal WHERE ugr_id = prm_ugr_id;
    RETURN;
  END IF;
  -- Delete relations present in DB not present in list
  DELETE FROM login.usergroup_portal WHERE ugr_id = prm_ugr_id AND por_id <> ALL(prm_por_ids);
  -- Add relations in list not yet in DB
  FOREACH t IN ARRAY prm_por_ids
  LOOP
    IF NOT EXISTS (SELECT 1 FROM login.usergroup_portal WHERE ugr_id = prm_ugr_id AND por_id = t) THEN
      INSERT INTO login.usergroup_portal (ugr_id, por_id) VALUES (prm_ugr_id, t);
    END IF;
  END LOOP;
END;
$$;
COMMENT ON FUNCTION login.usergroup_set_portals(prm_token integer, prm_ugr_id integer, prm_por_ids integer[]) 
IS 'Set authorized portals for a user group';

CREATE OR REPLACE FUNCTION login.usergroup_set_group_dossiers(
  prm_token integer, 
  prm_ugr_id integer, 
  prm_grp_ids integer[])
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  t integer;
BEGIN
  PERFORM login._token_assert(prm_token, '{users}');
  -- Raise an exception if some group belongs to an external organization
  IF EXISTS (SELECT 1 FROM organ.organization
               INNER JOIN organ.group USING(org_id)
               WHERE grp_id = ANY (prm_grp_ids)
               AND NOT org_internal) THEN
    RAISE EXCEPTION 'Groups should belong to internal organizations' 
      USING ERRCODE = 'data_exception';
  END IF;

  -- Raise an exception if entity does not exist
  IF NOT EXISTS (SELECT 1 FROM login.usergroup WHERE ugr_id = prm_ugr_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;
  -- If list is NULL, remove all relations
  IF prm_grp_ids ISNULL THEN
    DELETE FROM login.usergroup_group_dossiers WHERE ugr_id = prm_ugr_id;
    RETURN;
  END IF;
  -- Delete relations present in DB not present in list
  DELETE FROM login.usergroup_group_dossiers WHERE ugr_id = prm_ugr_id AND grp_id <> ALL(prm_grp_ids);
  -- Add relations in list not yet in DB
  FOREACH t IN ARRAY prm_grp_ids
  LOOP
    IF NOT EXISTS (SELECT 1 FROM login.usergroup_group_dossiers WHERE ugr_id = prm_ugr_id AND grp_id = t) THEN
      INSERT INTO login.usergroup_group_dossiers (ugr_id, grp_id) VALUES (prm_ugr_id, t);
    END IF;
  END LOOP;
END;
$$;
COMMENT ON FUNCTION login.usergroup_set_group_dossiers(prm_token integer, prm_ugr_id integer, prm_grp_ids integer[]) 
IS 'Set authorized groups for enabling an user in an usergroup to view the dossiers';

CREATE OR REPLACE FUNCTION login.usergroup_set_group_participants(
  prm_token integer, 
  prm_ugr_id integer, 
  prm_grp_ids integer[])
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  t integer;
BEGIN
  PERFORM login._token_assert(prm_token, '{users}');
  -- Raise an exception if some group belongs to an external organization
  IF EXISTS (SELECT 1 FROM organ.organization
               INNER JOIN organ.group USING(org_id)
               WHERE grp_id = ANY (prm_grp_ids)
               AND NOT org_internal) THEN
    RAISE EXCEPTION 'Groups should belong to internal organizations' 
      USING ERRCODE = 'data_exception';
  END IF;

  -- Raise an exception if entity does not exist
  IF NOT EXISTS (SELECT 1 FROM login.usergroup WHERE ugr_id = prm_ugr_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;
  -- If list is NULL, remove all relations
  IF prm_grp_ids ISNULL THEN
    DELETE FROM login.usergroup_group_participants WHERE ugr_id = prm_ugr_id;
    RETURN;
  END IF;
  -- Delete relations present in DB not present in list
  DELETE FROM login.usergroup_group_participants WHERE ugr_id = prm_ugr_id AND grp_id <> ALL(prm_grp_ids);
  -- Add relations in list not yet in DB
  FOREACH t IN ARRAY prm_grp_ids
  LOOP
    IF NOT EXISTS (SELECT 1 FROM login.usergroup_group_participants WHERE ugr_id = prm_ugr_id AND grp_id = t) THEN
      INSERT INTO login.usergroup_group_participants (ugr_id, grp_id) VALUES (prm_ugr_id, t);
    END IF;
  END LOOP;
END;
$$;
COMMENT ON FUNCTION login.usergroup_set_group_participants(prm_token integer, prm_ugr_id integer, prm_grp_ids integer[]) 
IS 'Set authorized groups for an user in an usergroup to see profiles of other participants';

CREATE OR REPLACE FUNCTION login.usergroup_set_topics(
  prm_token integer,
  prm_ugr_id integer,
  prm_top_ids integer[])
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  t integer;
BEGIN
  PERFORM login._token_assert(prm_token, '{users}');
  IF NOT EXISTS (SELECT 1 FROM login.usergroup WHERE ugr_id = prm_ugr_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;

  IF prm_top_ids ISNULL THEN
    DELETE FROM login.usergroup_topic WHERE ugr_id = prm_ugr_id;
    RETURN;
  END IF;

  DELETE FROM login.usergroup_topic WHERE ugr_id = prm_ugr_id AND top_id <> ALL(prm_top_ids);

  FOREACH t IN ARRAY prm_top_ids
  LOOP
    IF NOT EXISTS (SELECT 1 FROM login.usergroup_topic WHERE ugr_id = prm_ugr_id AND top_id = t) THEN
      INSERT INTO login.usergroup_topic (ugr_id, top_id) VALUES (prm_ugr_id, t);
    END IF;
  END LOOP;
END;
$$;
COMMENT ON FUNCTION login.usergroup_set_topics(prm_token integer, prm_ugr_id integer, prm_top_ids integer[])
IS 'Set authorized topics for an usergroup';

CREATE OR REPLACE FUNCTION login.usergroup_topic_set_rights(prm_token integer, prm_ugr_id integer, prm_top_id integer, prm_ugt_rights usergroup_topic_right[])
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, '{users}');
  UPDATE login.usergroup_topic SET ugt_rights = prm_ugt_rights 
    WHERE ugr_id = prm_ugr_id AND top_id = prm_top_id;
END;
$$;
COMMENT ON FUNCTION login.usergroup_topic_set_rights(prm_token integer, prm_ugr_id integer, prm_top_id integer, prm_ugt_rights usergroup_topic_right[]) IS 'Set rights for a usergroup/topic ';

CREATE OR REPLACE FUNCTION login.usergroup_topic_get_rights(prm_token integer, prm_ugr_id integer, prm_top_id integer)
RETURNS login.usergroup_topic_right[]
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  ret login.usergroup_topic_right[];
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  SELECT ugt_rights INTO ret FROM login.usergroup_topic WHERE ugr_id = prm_ugr_id AND top_id = prm_top_id;
  RETURN ret;
END;
$$;
COMMENT ON FUNCTION login.usergroup_topic_get_rights(prm_token integer, prm_ugr_id integer, prm_top_id integer) IS 'Returns the rights for a usergroup/topic';

CREATE OR REPLACE FUNCTION login.usergroup_portal_list(
  prm_token integer, 
  prm_ugr_id integer)
RETURNS SETOF portal.portal
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  RETURN QUERY SELECT portal.* FROM portal.portal
    INNER JOIN login.usergroup_portal USING(por_id)
    WHERE ugr_id = prm_ugr_id
    ORDER BY por_name;
END;
$$;
COMMENT ON FUNCTION login.usergroup_portal_list(prm_token integer, prm_ugr_id integer) 
IS 'Returns the portals authorized for a user group';

CREATE OR REPLACE FUNCTION login.usergroup_group_list(
  prm_token integer, 
  prm_ugr_id integer)
RETURNS SETOF organ.group
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  RETURN QUERY SELECT "group".* FROM organ.group
    INNER JOIN login.usergroup_group_dossiers USING (grp_id)
    WHERE ugr_id = prm_ugr_id
    ORDER BY grp_name;
END;
$$;
COMMENT ON FUNCTION login.usergroup_group_list(prm_token integer, prm_ugr_id integer) 
IS 'Returns the groups authorized for a user group';

CREATE OR REPLACE FUNCTION login.usergroup_topic_list(
  prm_token integer,
  prm_ugr_id integer)
RETURNS SETOF organ.topic
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  RETURN QUERY SELECT topic.* FROM organ.topic
    INNER JOIN login.usergroup_topic USING (top_id)
    WHERE ugr_id = prm_ugr_id
    ORDER BY top_name;
END;
$$;
COMMENT ON FUNCTION login.usergroup_topic_list(prm_token integer, prm_ugr_id integer)
IS 'Returns the topics authorized for an usergroup';

CREATE OR REPLACE FUNCTION login.usergroup_delete(prm_token integer, prm_ugr_id integer)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, '{users}');
  DELETE FROM login.usergroup_group_dossiers WHERE ugr_id = prm_ugr_id;
  DELETE FROM login.usergroup_group_participants WHERE ugr_id = prm_ugr_id;
  DELETE FROM login.usergroup_portal WHERE ugr_id = prm_ugr_id;
  DELETE FROM login.usergroup_topic WHERE ugr_id = prm_ugr_id;
  DELETE FROM login.usergroup WHERE ugr_id = prm_ugr_id;
END;
$$;
COMMENT ON FUNCTION login.usergroup_delete(prm_token integer, prm_ugr_id integer) IS 'Delete an usergroup and its links with groups and portals';

CREATE OR REPLACE FUNCTION login.usergroup_right_list()
RETURNS SETOF login.usergroup_right
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY SELECT unnest(enum_range(null::login.usergroup_right));
END;
$$;
COMMENT ON FUNCTION login.usergroup_right_list() IS 'Returns the list of usergroup rights';

CREATE OR REPLACE FUNCTION login.usergroup_topic_right_list()
RETURNS SETOF login.usergroup_topic_right
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY SELECT unnest(enum_range(null::login.usergroup_topic_right));
END;
$$;
COMMENT ON FUNCTION login.usergroup_topic_right_list() IS 'Returns the list of usergroup topic rights';
