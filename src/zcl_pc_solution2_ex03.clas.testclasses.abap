*"* use this source file for your ABAP unit test classes
CLASS ltcl_find_flights DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.

    CLASS-DATA the_carrier TYPE REF TO lcl_carrier. "1 declarar variable estática"
    CLASS-METHODS class_setup.                       "2 definir metodo estatico
    CLASS-DATA some_flight_data TYPE /lrn/cargoflight. "4 declarar atributo estático para almacenar registro de la tabla


    METHODS test_find_cargo_flight FOR TESTING RAISING cx_static_check.

ENDCLASS.


CLASS ltcl_find_flights IMPLEMENTATION.

  METHOD test_find_cargo_flight.

    the_carrier->find_cargo_flight(   "Si la instanciación ha salido ok Llamamos al método find_cargo_flight del objeto the_carrier


    exporting   "Parámetros de entrada que enviamos al método

      i_airport_from_id = some_flight_data-airport_from_id   "Aeropuerto origen leído de la base de datos
      i_airport_to_id   = some_flight_data-airport_to_id     "Aeropuerto destino leído de la base de datos
      i_from_date       = some_flight_data-flight_date       "Fecha a partir de la cual buscamos el vuelo
      i_cargo           = 1                                  "Capacidad mínima de carga requerida (1 kg)

    importing   "Parámetros de salida que recibimos del método

      e_flight     = data(flight)       "Referencia al objeto vuelo encontrado (declaración inline)
      e_days_later = data(days_later)   "Número de días hasta encontrar el vuelo adecuado

  ).   "Fin de la llamada al método

    cl_abap_unit_assert=>assert_bound(   "Verifica que la referencia al objeto no sea inicial
      act = flight                      "Valor actual: la referencia devuelta por el método
      msg = `Method find_cargo_flight does not return a result`  "Mensaje que se muestra si la aserción falla
    ).                                   "Si 'flight' no está BOUND, el test falla

    cl_abap_unit_assert=>assert_equals(  "Verifica que dos valores sean iguales
      act = days_later                   "Valor actual calculado por el método
      exp = 0                            "Valor esperado (debería ser 0 días)
      msg = `Method find_cargo_flight returns wrong result`  "Mensaje si el valor no coincide
    ).                                   "Si days_later <> 0, el test falla


*    cl_abap_unit_assert=>fail( 'Implement your first test here' ).
  ENDMETHOD.



  METHOD class_setup.

    SELECT SINGLE   "Leemos un único registro de la base de datos
        FROM /lrn/cargoflight   "Tabla de base de datos que contiene vuelos de carga
        FIELDS carrier_id, connection_id, flight_date,
              airport_from_id, airport_to_id  "Campos específicos que queremos recuperar
*      INTO @DATA(some_flight_data).   "Guardamos el resultado en una variable interna creada inline
         INTO CORRESPONDING FIELDS OF @some_flight_data. "Use esta caja que ya existe y rellene lo que coincida


    IF sy-subrc <> 0. "Si no hay datos en la tabla /LRN/CARGOFLIGHT, notifique el test como fallido.
      cl_abap_unit_assert=>fail( `No data in table /lrn/CARGOFLIGHT` ).
    ENDIF.


    TRY.  "Inicio de un bloque para controlar posibles excepciones

*        DATA(the_carrier) = NEW lcl_carrier(  "Creamos una referencia a objeto y lo instanciamos
        the_carrier = NEW lcl_carrier(
            i_carrier_id = some_flight_data-carrier_id ).  "Pasamos el carrier_id leído de la base de datos al constructor

      CATCH cx_abap_invalid_value.  "Capturamos la excepción si el carrier_id no es válido

        cl_abap_unit_assert=>fail(  "Forzamos el fallo del test de unidad
            `Unable to instantiate lcl_carrier` ).  "Mensaje que se mostrará en el resultado del test

    ENDTRY.  "Fin del bloque de control de excepciones


  endmethod.

ENDCLASS.
