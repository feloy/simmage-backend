CREATE OR REPLACE FUNCTION documents.document_add(
  prm_token integer, 
  prm_par_id_responsible integer, 
  prm_dty_id integer, 
  prm_title text, 
  prm_description text, 
  prm_status documents.document_status, 
  prm_deadline date,
  prm_execution_date date, 
  prm_validity_date date, 
  prm_file text, 
  prm_topics integer[], 
  prm_dossiers integer[])
RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  new_id integer;
  topics integer[];
  author_id integer;
BEGIN
  PERFORM login._token_assert(prm_token, null);

  IF prm_dty_id IS NOT NULL THEN
    SELECT array_agg(top_id) INTO topics FROM documents.document_type_topic WHERE dty_id = prm_dty_id;
  ELSE
    topics = prm_topics;
  END IF;

  SELECT par_id INTO author_id FROM login.user WHERE usr_token = prm_token;

  INSERT INTO documents.document (
    par_id_responsible,
    dty_id,
    doc_title,
    doc_description,
    doc_status,
    doc_deadline,
    doc_execution_date,
    doc_validity_date,
    doc_file,
    doc_author,
    doc_creation_date
   ) VALUES (
    prm_par_id_responsible,
    prm_dty_id,
    prm_title,
    prm_description,
    prm_status,
    prm_deadline,
    prm_execution_date,
    prm_validity_date,
    prm_file,
    author_id,
    CURRENT_TIMESTAMP
   ) RETURNING doc_id INTO new_id;

  PERFORM documents.document_set_topics(prm_token, new_id, topics);
  PERFORM documents.document_set_dossiers(prm_token, new_id, prm_dossiers);
  PERFORM documents.document_responsible_attribution_update(prm_token, new_id, NULL, prm_par_id_responsible);
  RETURN new_id;
END;
$$;
COMMENT ON FUNCTION documents.document_add(
  prm_token integer,
  prm_par_id_responsible integer,
  prm_dty_id integer,
  prm_title text,
  prm_description text,
  prm_status documents.document_status,
  prm_deadline date,
  prm_execution_date date,
  prm_validity_date date,
  prm_file text,
  prm_topics integer[],
  prm_dossiers integer[])
 IS 'Add a new document';

CREATE OR REPLACE FUNCTION documents.document_update(
  prm_token integer, prm_doc_id integer, prm_par_id_responsible integer, prm_dty_id integer,
  prm_title text, prm_description text, prm_status documents.document_status,
  prm_deadline date, prm_execution_date date, prm_validity_date date,
  prm_file text, prm_topics integer[], prm_dossiers integer[]
)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  topics integer[];
  old_responsible integer;
  new_responsible integer := null;
BEGIN
  PERFORM login._token_assert(prm_token, null);
  IF NOT EXISTS (SELECT 1 FROM documents.document WHERE doc_id = prm_doc_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;
  IF prm_dty_id IS NOT NULL THEN
    SELECT array_agg(top_id) INTO topics FROM documents.document_type_topic WHERE dty_id = prm_dty_id;
  ELSE
    topics = prm_topics;
  END IF;
 
  SELECT par_id_responsible INTO old_responsible FROM documents.document WHERE doc_id = prm_doc_id;

  UPDATE documents.document SET
    par_id_responsible = prm_par_id_responsible,
    dty_id = prm_dty_id,
    doc_title = prm_title,
    doc_description = prm_description,
    doc_status = prm_status,
    doc_deadline = prm_deadline,
    doc_execution_date = prm_execution_date,
    doc_validity_date = prm_validity_date,
    doc_file = prm_file
    WHERE doc_id = prm_doc_id;

    new_responsible := prm_par_id_responsible;

  PERFORM documents.document_set_topics(prm_token, prm_doc_id, topics);
  PERFORM documents.document_set_dossiers(prm_token, prm_doc_id, prm_dossiers);
  IF new_responsible != old_responsible THEN
    PERFORM documents.document_responsible_attribution_update(prm_token, prm_doc_id, old_responsible, new_responsible);
  END IF;
END;
$$;
COMMENT ON FUNCTION documents.document_update(
  prm_token integer, prm_doc_id integer, prm_par_id_responsible integer, prm_dty_id integer,
  prm_title text, prm_description text, prm_status documents.document_status,
  prm_deadline date, prm_execution_date date, prm_validity_date date,
  prm_file text, prm_topics integer[], prm_dossiers integer[]
) IS 'update a document informations';

CREATE OR REPLACE FUNCTION documents.document_set_topics(
  prm_token integer,
  prm_doc_id integer,
  prm_top_ids integer[])
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  t integer;
BEGIN
  PERFORM login._token_assert(prm_token, null);
  IF NOT EXISTS (SELECT 1 FROM documents.document WHERE doc_id = prm_doc_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;

  IF prm_top_ids ISNULL THEN
    DELETE FROM documents.document_topic WHERE doc_id = prm_doc_id;
    RETURN;
  END IF;

  DELETE FROM documents.document_topic WHERE doc_id = prm_doc_id AND top_id <> ALL(prm_top_ids);

  FOREACH t IN ARRAY prm_top_ids
  LOOP
    IF NOT EXISTS (SELECT 1 FROM documents.document_topic WHERE doc_id = prm_doc_id AND top_id = t) THEN
      INSERT INTO documents.document_topic (doc_id, top_id) VALUES (prm_doc_id, t);
    END IF;
  END LOOP;
END;
$$;
COMMENT ON FUNCTION documents.document_set_topics(prm_token integer, prm_doc_id integer, prm_top_ids integer[])
IS 'Set topics of a document';

CREATE OR REPLACE FUNCTION documents.document_set_dossiers(
  prm_token integer,
  prm_doc_id integer,
  prm_dos_ids integer[])
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  t integer;
BEGIN
  PERFORM login._token_assert(prm_token, null);
  IF NOT EXISTS (SELECT 1 FROM documents.document WHERE doc_id = prm_doc_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;

  IF prm_dos_ids ISNULL THEN
    DELETE FROM documents.document_dossier WHERE doc_id = prm_doc_id;
    RETURN;
  END IF;

  DELETE FROM documents.document_dossier WHERE doc_id = prm_doc_id AND dos_id <> ALL(prm_dos_ids);

  FOREACH t IN ARRAY prm_dos_ids
  LOOP
    IF NOT EXISTS (SELECT 1 FROM documents.document_dossier WHERE doc_id = prm_doc_id AND dos_id = t) THEN
      INSERT INTO documents.document_dossier (doc_id, dos_id) VALUES (prm_doc_id, t);
    END IF;
  END LOOP;
END;
$$;
COMMENT ON FUNCTION documents.document_set_dossiers(prm_token integer, prm_doc_id integer, prm_dos_ids integer[])
IS 'Set dossiers of a document';

CREATE OR REPLACE FUNCTION documents.document_get(prm_token integer, prm_doc_id integer)
RETURNS documents.document
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  ret documents.document;
BEGIN
  PERFORM login._token_assert(prm_token, null);
  SELECT * INTO ret FROM documents.document WHERE doc_id = prm_doc_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;
  RETURN ret;
END;
$$;
COMMENT ON FUNCTION documents.document_get(prm_token integer, prm_doc_id integer) IS 'Returns information about a document';

CREATE OR REPLACE FUNCTION documents.document_topic_list(prm_token integer, prm_doc_id integer)
RETURNS SETOF organ.topic
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, null);
  RETURN QUERY SELECT topic.* FROM organ.topic
    INNER JOIN documents.document_topic USING (top_id)
    WHERE doc_id = prm_doc_id
    ORDER BY top_name;
END;
$$;
COMMENT ON FUNCTION documents.document_topic_list(prm_token integer, prm_doc_id integer) IS 'Retunrs the topics of a document';

CREATE OR REPLACE FUNCTION documents.document_dossier_list(prm_token integer, prm_doc_id integer)
RETURNS SETOF organ.dossier
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, null);
  RETURN QUERY SELECT dossier.* FROM organ.dossier
    INNER JOIN documents.document_dossier USING (dos_id)
    WHERE doc_id = prm_doc_id
    ORDER BY dos_id;
END;
$$;
COMMENT ON FUNCTION documents.document_dossier_list(prm_token integer, prm_doc_id integer) IS 'Retunrs the dossiers of a document';

-- 
-- JSON
-- 
CREATE OR REPLACE FUNCTION documents.document_topic_json(prm_token integer, prm_doc_id integer, req json)
RETURNS json
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  ret json;
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  SELECT array_to_json(array_agg(row_to_json(d))) INTO ret
    FROM (SELECT
      CASE WHEN (req->>'top_id') IS NULL THEN NULL ELSE top_id END as top_id, 
      CASE WHEN (req->>'top_name') IS NULL THEN NULL ELSE  top_name END as top_name, 
      CASE WHEN (req->>'top_description') IS NULL THEN NULL ELSE top_description END as top_description,
      CASE WHEN (req->>'top_icon') IS NULL THEN NULL ELSE top_icon END as top_icon,
      CASE WHEN (req->>'top_color') IS NULL THEN NULL ELSE top_color END as top_color
      FROM organ.topic 
      INNER JOIN documents.document_topic USING (top_id) 
      WHERE doc_id = prm_doc_id
      ORDER BY top_name) d;
  RETURN ret;
END;
$$;
COMMENT ON FUNCTION documents.document_topic_json(prm_token integer, prm_doc_id integer, req json) IS 'Returns the topics of a document as json';

CREATE OR REPLACE FUNCTION documents.document_dossier_json(prm_token integer, prm_doc_id integer, req json)
RETURNS json
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  ret json;
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  SELECT array_to_json(array_agg(row_to_json(d))) INTO ret
    FROM (SELECT
      CASE WHEN (req->>'dos_id') IS NULL THEN NULL ELSE dos_id END as dos_id, 
      CASE WHEN (req->>'dos_firstname') IS NULL THEN NULL ELSE dos_firstname END as dos_firstname, 
      CASE WHEN (req->>'dos_lastname') IS NULL THEN NULL ELSE dos_lastname END as dos_lastname, 
      CASE WHEN (req->>'dos_birthdate') IS NULL THEN NULL ELSE dos_birthdate END as dos_birthdate, 
      CASE WHEN (req->>'dos_gender') IS NULL THEN NULL ELSE dos_gender END as dos_gender, 
      CASE WHEN (req->>'dos_grouped') IS NULL THEN NULL ELSE dos_grouped END as dos_grouped, 
      CASE WHEN (req->>'dos_external') IS NULL THEN NULL ELSE dos_external END as dos_external, 
      CASE WHEN (req->>'dos_groupname') IS NULL THEN NULL ELSE dos_groupname END as dos_groupname 
      FROM organ.dossier
      INNER JOIN documents.document_dossier USING (dos_id) 
      WHERE doc_id = prm_doc_id
      ORDER BY dos_id) d;
  RETURN ret;
END;
$$;
COMMENT ON FUNCTION documents.document_dossier_json(prm_token integer, prm_doc_id integer, req json) IS 'Returns the dossiers of a document as json';

CREATE OR REPLACE FUNCTION documents.document_json(prm_token integer, prm_doc_ids integer[], req json)
RETURNS json
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  ret json;
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  SELECT array_to_json(array_agg(row_to_json(d))) INTO ret
  FROM (SELECT
    CASE WHEN (req->>'doc_id') IS NULL THEN NULL ELSE doc_id END as doc_id,
    CASE WHEN (req->>'par_id_responsible') IS NULL THEN NULL ELSE par_id_responsible END as par_id_responsible,
    CASE WHEN (req->>'dty_id') IS NULL THEN NULL ELSE dty_id END as dty_id,
    CASE WHEN (req->>'dty_name') IS NULL THEN NULL ELSE dty_name END as dty_name,
    CASE WHEN (req->>'doc_title') IS NULL THEN NULL ELSE doc_title END as doc_title,
    CASE WHEN (req->>'doc_description') IS NULL THEN NULL ELSE doc_description END as doc_description,
    CASE WHEN (req->>'doc_status') IS NULL THEN NULL ELSE doc_status END as doc_status,
    CASE WHEN (req->>'doc_deadline') IS NULL THEN NULL ELSE doc_deadline END as doc_deadline,
    CASE WHEN (req->>'doc_execution_date') IS NULL THEN NULL ELSE doc_execution_date END as doc_execution_date,
    CASE WHEN (req->>'doc_validity_date') IS NULL THEN NULL ELSE doc_validity_date END as doc_validity_date,
    CASE WHEN (req->>'doc_file') IS NULL THEN NULL ELSE doc_file END as doc_file,
    CASE WHEN (req->>'doc_creation_date') IS NULL THEN NULL ELSE doc_creation_date END as doc_creation_date,
    CASE WHEN (req->>'author') IS NULL THEN NULL ELSE
      organ.participant_json(prm_token, doc_author, req->'author') END as author,
    CASE WHEN (req->>'responsible') IS NULL THEN NULL ELSE
      organ.participant_json(prm_token, par_id_responsible, req->'responsible') END as responsible,
    CASE WHEN (req->>'topics') IS NULL THEN NULL ELSE
      documents.document_topic_json(prm_token, doc_id, req->'topics') END as topics,
    CASE WHEN (req->>'dossiers') IS NULL THEN NULL ELSE
      documents.document_dossier_json(prm_token, doc_id, req->'dossiers') END as dossiers,
    CASE WHEN (req->>'responsible_history') IS NULL THEN NULL ELSE
      documents.document_responsible_history_json(prm_token, doc_id, req->'responsible_history') END as responsible_history
    FROM documents.document
      LEFT JOIN documents.document_type USING(dty_id)
      WHERE doc_id = ANY(prm_doc_ids)
  ) d;
  RETURN ret;
END;
$$;
COMMENT ON FUNCTION documents.document_json(prm_token integer, prm_doc_ids integer[], req json) IS 'Returns information about a document as json';

CREATE OR REPLACE FUNCTION documents.document_in_view_list(
  prm_token integer, 
  prm_dov_id integer, 
  prm_grp_id integer, 
  req json)
RETURNS json
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  the_doc_id integer;
  
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  RETURN documents.document_json(prm_token, (SELECT ARRAY(
   SELECT DISTINCT doc_id FROM documents.document
    INNER JOIN documents.document_topic USING(doc_id)
    INNER JOIN documents.documentsview_topic USING(top_id)
    INNER JOIN documents.documentsview USING(dov_id)
    INNER JOIN documents.document_dossier USING(doc_id)
    INNER JOIN organ.dossiers_authorized_for_user(prm_token) 
      ON dossiers_authorized_for_user = document_dossier.dos_id
    WHERE dov_id = prm_dov_id AND
      (prm_grp_id IS NULL OR 
       prm_grp_id = ANY(SELECT grp_id FROM organ.dossier_assignment WHERE dossier_assignment.dos_id = document_dossier.dos_id)
    ))), req);
END;
$$;
COMMENT ON FUNCTION documents.document_in_view_list(
  prm_token integer, 
  prm_dov_id integer, 
  prm_grp_id integer, 
  req json)
 IS 'Returns the documents visible in a documents view';

CREATE OR REPLACE FUNCTION documents.document_delete(prm_token integer, prm_doc_id integer)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  PERFORM login._token_assert(prm_token, null);
  IF NOT EXISTS (SELECT 1 FROM documents.document WHERE doc_id = prm_doc_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;

  DELETE FROM documents.document_responsible_attribution WHERE doc_id = prm_doc_id;
  DELETE FROM documents.document_dossier WHERE doc_id = prm_doc_id;
  DELETE FROM documents.document_topic WHERE doc_id = prm_doc_id;
  DELETE FROM documents.document WHERE doc_id = prm_doc_id;
END;
$$;
COMMENT ON FUNCTION documents.document_delete(prm_token integer, prm_doc_id integer) IS 'Delete a document and its links with any topic or dossier';

CREATE OR REPLACE FUNCTION documents.document_status_list()
RETURNS SETOF documents.document_status
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY SELECT unnest(enum_range(null::documents.document_status));
END;
$$;
COMMENT ON FUNCTION documents.document_status_list() IS 'Returns the list of document statuses';

CREATE OR REPLACE FUNCTION documents.document_participant_list(prm_token integer, req json)
RETURNS json
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  ret json;
  participant integer;
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  SELECT par_id INTO participant FROM login.user WHERE usr_token = prm_token;
  RETURN documents.document_json(prm_token, (SELECT ARRAY(
    SELECT DISTINCT doc_id FROM documents.document
      LEFT JOIN documents.document_dossier USING(doc_id)
      WHERE doc_author = participant OR par_id_responsible = participant OR document_dossier.doc_id IS NULL
      )), req);
END;
$$;
COMMENT ON FUNCTION documents.document_participant_list(prm_token integer, req json) IS 'Returns the notes attributed to or created by the current user';

CREATE OR REPLACE FUNCTION documents.document_responsible_attribution_update(prm_token integer, prm_doc_id integer, prm_old_responsible integer, prm_new_responsible integer)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  attribution_ts timestamp with time zone;
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  IF prm_old_responsible IS NOT NULL AND NOT EXISTS (SELECT 1 FROM documents.document_responsible_attribution WHERE doc_id = prm_doc_id AND par_id_responsible = prm_old_responsible) THEN
    RAISE EXCEPTION USING ERRCODE = 'no_data_found';
  END IF;

  attribution_ts := CURRENT_TIMESTAMP;

  IF prm_old_responsible IS NOT NULL THEN
    UPDATE documents.document_responsible_attribution SET
      dra_achievement_date = attribution_ts
      WHERE doc_id = prm_doc_id
      AND par_id_responsible = prm_old_responsible;
  END IF;

  IF prm_new_responsible IS NOT NULL THEN
    INSERT INTO documents.document_responsible_attribution (doc_id, par_id_responsible, dra_attribution_date)
      VALUES (prm_doc_id, prm_new_responsible, attribution_ts);
  END IF;
END;
$$;
COMMENT ON FUNCTION documents.document_responsible_attribution_update(prm_token integer, prm_doc_id integer, prm_old_responsible integer, prm_new_responsible integer) IS 'Makes an history of document responsibles attribution';

CREATE OR REPLACE FUNCTION documents.document_responsible_history_json(prm_token integer, prm_doc_id integer, req json)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  ret json;
BEGIN
  PERFORM login._token_assert(prm_token, NULL);
  SELECT array_to_json(array_agg(row_to_json(d))) INTO ret
  FROM (SELECT
    CASE WHEN (req->>'responsible') IS NULL THEN NULL ELSE
      organ.participant_json(prm_token, par_id_responsible, req->'responsible') END as responsible,
    CASE WHEN (req->>'dra_attribution_date') IS NULL THEN NULL ELSE dra_attribution_date END as dra_attribution_date,
    CASE WHEN (req->>'dra_achievement_date') IS NULL THEN NULL ELSE dra_achievement_date END as dra_achievement_date
    FROM documents.document_responsible_attribution
    WHERE doc_id = prm_doc_id
    ORDER BY dra_attribution_date
  ) d;
  RETURN ret;
END;
$$;
COMMENT ON FUNCTION documents.document_responsible_history_json(prm_token integer, prm_doc_id integer, req json) IS 'Returns the responsible history of a document';
