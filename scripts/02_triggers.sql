--- CREACION DE TRIGGERS ------
--- Trigger para autoinscripción en actividades al confirmar pago de inscripción al evento

CREATE OR REPLACE TRIGGER trg_auto_inscripcion_actividad
AFTER INSERT OR UPDATE ON UEP_TAB_EVENTOS_INSCRIPCIONES
FOR EACH ROW
DECLARE
  CURSOR c_actividades IS
    SELECT ACTIVIDAD_ID
    FROM UEP_TAB_ACTIVIDADES
    WHERE ID_EVENTO = :NEW.ID_EVENTO
      AND AUTOINSCRIPCION = 'S'; -- Solo actividades autoinscribibles
  v_count NUMBER;
BEGIN
  -- Ejecutar en dos casos:
  IF (INSERTING AND :NEW.PAGADO = 3) OR 
     (UPDATING AND (:OLD.PAGADO IS NULL OR :OLD.PAGADO != 3) AND :NEW.PAGADO = 3) THEN
     
    FOR actividad IN c_actividades LOOP
      -- Verificar si ya existe inscripción
      SELECT COUNT(*)
      INTO v_count
      FROM UEP_TAB_ACTIVIDAD_ASISTENCIA
      WHERE USUARIO_CEDULA = :NEW.PERSONA_CEDULA
        AND ACTIVIDAD_ID = actividad.ACTIVIDAD_ID;

      -- Insertar si no existe
      IF v_count = 0 THEN
        INSERT INTO UEP_TAB_ACTIVIDAD_ASISTENCIA (
          USUARIO_CEDULA,
          ACTIVIDAD_ID,
          FECHA_INSCRIPCION,
          ESTADO,
          ASISTENCIA_REGISTRADA,
          SALIDA_REGISTRADA,
          CODIGO_QR
        ) VALUES (
          :NEW.PERSONA_CEDULA,
          actividad.ACTIVIDAD_ID,
          SYSDATE,
          'A',
          'N',
          'N',
          :NEW.CODIGO_QR
        );
      END IF;
    END LOOP;
  END IF;
END;
/

--- Trigger para autoinscripción en actividades al marcar una actividad como autoinscribible---
CREATE OR REPLACE TRIGGER trg_autoinscripcion_nueva_act
AFTER INSERT OR UPDATE ON UEP_TAB_ACTIVIDADES
FOR EACH ROW
DECLARE
  CURSOR c_usuarios IS
    SELECT PERSONA_CEDULA
    FROM UEP_TAB_EVENTOS_INSCRIPCIONES
    WHERE ID_EVENTO = :NEW.ID_EVENTO
      AND PAGADO = 3;

  v_count NUMBER;
  v_codigo_qr VARCHAR2(200);

BEGIN
  -- Activamos el log
  DBMS_OUTPUT.PUT_LINE('Trigger activado para actividad ID: ' || :NEW.ACTIVIDAD_ID);

  IF (
    INSERTING AND :NEW.AUTOINSCRIPCION = 'S'
  ) OR (
    UPDATING AND :NEW.AUTOINSCRIPCION = 'S' AND ( :OLD.AUTOINSCRIPCION IS NULL OR :OLD.AUTOINSCRIPCION != 'S' )
  ) THEN
    DBMS_OUTPUT.PUT_LINE('Condiciones de autoinscripción cumplidas.');

    FOR usuario IN c_usuarios LOOP
      DBMS_OUTPUT.PUT_LINE('Procesando usuario: ' || usuario.PERSONA_CEDULA);
    
      SELECT CODIGO_QR
      INTO v_codigo_qr
      FROM UEP_TAB_EVENTOS_INSCRIPCIONES
      WHERE ID_EVENTO = :NEW.ID_EVENTO
        AND PERSONA_CEDULA = usuario.PERSONA_CEDULA
        AND PAGADO = 3
      AND ROWNUM = 1; -- Asegúrate de que haya solo un registro que coincida
        
      SELECT COUNT(*)
      INTO v_count
      FROM UEP_TAB_ACTIVIDAD_ASISTENCIA
      WHERE USUARIO_CEDULA = usuario.PERSONA_CEDULA
        AND ACTIVIDAD_ID = :NEW.ACTIVIDAD_ID;

      IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Insertando inscripción para usuario: ' || usuario.PERSONA_CEDULA);

        INSERT INTO UEP_TAB_ACTIVIDAD_ASISTENCIA (
          USUARIO_CEDULA,
          ACTIVIDAD_ID,
          FECHA_INSCRIPCION,
          ESTADO,
          ASISTENCIA_REGISTRADA,
          SALIDA_REGISTRADA,
          CODIGO_QR
        ) VALUES (
          usuario.PERSONA_CEDULA,
          :NEW.ACTIVIDAD_ID,
          SYSDATE,
          'A',
          'N',
          'N',
          v_codigo_qr
        );
      ELSE
        DBMS_OUTPUT.PUT_LINE('Usuario ya inscrito: ' || usuario.PERSONA_CEDULA);
      END IF;
    END LOOP;
  ELSE
    DBMS_OUTPUT.PUT_LINE('Condiciones no cumplidas, no se procesó.');
  END IF;
END;
/

--- Trigger para asignar código QR en la tabla de asistencia basado en la inscripción ---

CREATE OR REPLACE TRIGGER trg_auto_qr_asistencia
BEFORE INSERT ON UEP_TAB_ACTIVIDAD_ASISTENCIA
FOR EACH ROW
DECLARE
  v_evento_id   NUMBER;
  v_codigo_qr   VARCHAR2(100);
BEGIN
  -- Solo si viene nulo o vacío el código QR
  IF :NEW.CODIGO_QR IS NULL OR TRIM(:NEW.CODIGO_QR) = '' THEN
    -- Obtener el ID_EVENTO correspondiente a la ACTIVIDAD_ID
    SELECT ID_EVENTO
    INTO v_evento_id
    FROM UEP_TAB_ACTIVIDADES
    WHERE ACTIVIDAD_ID = :NEW.ACTIVIDAD_ID;

    -- Buscar el código QR correspondiente a ese evento y cédula
    SELECT CODIGO_QR
    INTO v_codigo_qr
    FROM UEP_TAB_EVENTOS_INSCRIPCIONES
    WHERE ID_EVENTO = v_evento_id
      AND PERSONA_CEDULA = :NEW.USUARIO_CEDULA;

    -- Asignarlo al nuevo registro
    :NEW.CODIGO_QR := v_codigo_qr;
  END IF;
END;
/

--- Trigger para generar código QR único en inscripciones a eventos ---

CREATE OR REPLACE TRIGGER trg_gen_qr_inscripcion
BEFORE INSERT ON UEP_TAB_EVENTOS_INSCRIPCIONES
FOR EACH ROW
BEGIN
  -- Generar un hash SHA-256 y convertirlo en un valor hexadecimal
  :NEW.CODIGO_QR := 
    SUBSTR(RAWTOHEX(DBMS_CRYPTO.HASH(UTL_RAW.CAST_TO_RAW(:NEW.ID_EVENTO || ':' || :NEW.PERSONA_CEDULA), DBMS_CRYPTO.HASH_SH256)), 1, 8) || '-' ||
    SUBSTR(RAWTOHEX(DBMS_CRYPTO.HASH(UTL_RAW.CAST_TO_RAW(:NEW.ID_EVENTO || ':' || :NEW.PERSONA_CEDULA), DBMS_CRYPTO.HASH_SH256)), 9, 4) || '-' ||
    SUBSTR(RAWTOHEX(DBMS_CRYPTO.HASH(UTL_RAW.CAST_TO_RAW(:NEW.ID_EVENTO || ':' || :NEW.PERSONA_CEDULA), DBMS_CRYPTO.HASH_SH256)), 13, 4) || '-' ||
    SUBSTR(RAWTOHEX(DBMS_CRYPTO.HASH(UTL_RAW.CAST_TO_RAW(:NEW.ID_EVENTO || ':' || :NEW.PERSONA_CEDULA), DBMS_CRYPTO.HASH_SH256)), 17, 4) || '-' ||
    SUBSTR(RAWTOHEX(DBMS_CRYPTO.HASH(UTL_RAW.CAST_TO_RAW(:NEW.ID_EVENTO || ':' || :NEW.PERSONA_CEDULA), DBMS_CRYPTO.HASH_SH256)), 21, 12);
END;
/