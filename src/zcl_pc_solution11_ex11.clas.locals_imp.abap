*"* use this source file for the definition and implementation of
*"* local helper classes, interface definitions and type
*"* declarations

CLASS lcl_passenger_flight DEFINITION .

  PUBLIC SECTION.

    DATA carrier_id    TYPE /dmo/carrier_id       READ-ONLY.
    DATA connection_id TYPE /dmo/connection_id    READ-ONLY.
    DATA flight_date   TYPE /dmo/flight_date      READ-ONLY.

    METHODS constructor
      IMPORTING
        i_carrier_id    TYPE /dmo/carrier_id
        i_connection_id TYPE /dmo/connection_id
        i_flight_date   TYPE /dmo/flight_date.

    TYPES:
      BEGIN OF st_connection_details,
        airport_from_id TYPE /dmo/airport_from_id,
        airport_to_id   TYPE /dmo/airport_to_id,
        departure_time  TYPE /dmo/flight_departure_time,
        arrival_time    TYPE /dmo/flight_departure_time,
        duration        TYPE i, "ampliamos la definición del tipo de estructura incluyendo
        "el componente durantion en e atributo st_connections details
        "a continuación actualizar método get_description
      END OF st_connection_details.

    TYPES
      tt_flights TYPE STANDARD TABLE OF REF TO lcl_passenger_flight WITH DEFAULT KEY.

    METHODS: get_connection_details
      RETURNING
        VALUE(r_result) TYPE st_connection_details.

    METHODS
      get_free_seats
        RETURNING
          VALUE(r_result) TYPE i.

    METHODS
      get_description RETURNING VALUE(r_result) TYPE string_table.

    CLASS-METHODS class_constructor.
    CLASS-METHODS
      get_flights_by_carrier
        IMPORTING
          i_carrier_id    TYPE /dmo/carrier_id
        RETURNING
          VALUE(r_result) TYPE tt_flights.

  PROTECTED SECTION.
  PRIVATE SECTION.

    DATA planetype TYPE /dmo/plane_type_id.

    DATA seats_max  TYPE /dmo/plane_seats_max.
    DATA seats_occ  TYPE /dmo/plane_seats_occupied.
    DATA seats_free TYPE i.

    DATA price TYPE /dmo/flight_price.
    CLASS-DATA currency TYPE /dmo/currency_code VALUE 'EUR'.

    TYPES: BEGIN OF st_flights_buffer,
             carrier_id     TYPE /lrn/passflight-carrier_id,
             connection_id  TYPE /lrn/passflight-connection_id,
             flight_date    TYPE /lrn/passflight-flight_date,
             plane_type_id  TYPE /lrn/passflight-plane_type_id,
             seats_max      TYPE /lrn/passflight-seats_max,
             seats_occupied TYPE /lrn/passflight-seats_occupied,
             seats_free     TYPE i, "añadir un componente
             price          TYPE /lrn/passflight-price,
             currency_code  TYPE /lrn/passflight-currency_code,
           END OF st_flights_buffer.
    CLASS-DATA: flights_buffer TYPE TABLE OF st_flights_buffer.


    DATA connection_details TYPE st_connection_details.

    TYPES:
      BEGIN OF st_connections_buffer,
        carrier_id      TYPE /dmo/carrier_id,
        connection_id   TYPE /dmo/connection_id,
        airport_from_id TYPE /dmo/airport_from_id,
        airport_to_id   TYPE /dmo/airport_to_id,
        departure_time  TYPE /dmo/flight_departure_time,
        arrival_time    TYPE /dmo/flight_departure_time,
        timzone_from TYPE timezone, "añadir componente de uso horario incluido en SELECT
        timzone_to TYPE timezone, "añadir componente de uso horario incluido en SELECT
        duration        TYPE i,   "incluimos componenente duración
      END OF st_connections_buffer.

    CLASS-DATA connections_buffer TYPE TABLE OF st_connections_buffer.

ENDCLASS.

CLASS lcl_passenger_flight IMPLEMENTATION.

  METHOD class_constructor.

*    " Eliminar SELECT redudante
*    SELECT                          "leer en BD e incluir en TI
*      FROM /lrn/airport
*    FIELDS airport_id, timzone
*      INTO TABLE @DATA(airports).

    SELECT
      FROM /lrn/connection AS c "Añadir alias para la fuente de datos
      LEFT OUTER JOIN /lrn/airport AS f "Trae todas las conexiones de vuelo
                                    "aunque no exista un aeropuerto correspondiente en la tabla /lrn/airport.
      ON c~airport_from_id = f~airport_id " añadir condición de conexión
      LEFT OUTER JOIN /lrn/airport AS t "Segundo JOIN con la misma tabla para leer detalles del aeropuerto destino
      ON c~airport_to_id = t~airport_id
    FIELDS carrier_id, connection_id,
           airport_from_id, airport_to_id, departure_time, arrival_time,
           f~timzone AS timzone_from,  "Añadir uso horario de aeropuerto de salida
           t~timzone AS timzone_to "Añadir uso horario de aeropuerto de destino
      INTO TABLE @connections_buffer.

    DATA(today) = cl_abap_context_info=>get_system_date(  ). "obtener fecha actual sistema

    LOOP AT connections_buffer INTO DATA(connection). "recorrer cada conexión -> area de trabajo

      CONVERT DATE today  " Convertir hora local a tiempo universal
              TIME connection-departure_time
*              TIME ZONE airports[ airport_id = connection-airport_from_id ]-timzone " no accedemos a TI sino directamente a componente
              TIME ZONE connection-timzone_from " no accedemos a TI sino directamente a componente
              INTO UTCLONG DATA(departure_utclong).

      CONVERT DATE today "Convertir hora local a tiempo universal
              TIME connection-arrival_time
*              TIME ZONE airports[ airport_id = connection-airport_to_id ]-timzone " no accedemos a TI sino directamente a componente
              TIME ZONE connection-timzone_to " no accedemos a TI sino directamente a componente
              INTO UTCLONG DATA(arrival_utclong).

      connection-duration = utclong_diff( high = arrival_utclong      "Calcular diferencia
                                          low = departure_utclong
                                          ) / 60.

      MODIFY connections_buffer FROM connection TRANSPORTING duration. "Actualizar tabla interna"

    ENDLOOP.

  ENDMETHOD.

  METHOD get_flights_by_carrier.

*    SELECT
*      FROM /lrn/passflight
*    FIELDS carrier_id, connection_id, flight_date
*     WHERE carrier_id    = @i_carrier_id
*      INTO TABLE @DATA(keys).

    SELECT
      FROM /lrn/passflight
    FIELDS carrier_id, connection_id, flight_date,
           plane_type_id, seats_max, seats_occupied,
           seats_max - seats_occupied AS seats_free, "cálculo de las plazas libres
           price, currency_code
     WHERE carrier_id = @i_carrier_id
      INTO TABLE @flights_buffer.


    LOOP AT flights_buffer INTO DATA(flight).
      APPEND NEW lcl_passenger_flight( i_carrier_id    = flight-carrier_id
                                       i_connection_id = flight-connection_id
                                       i_flight_date   = flight-flight_date )
              TO r_result.
    ENDLOOP.

  ENDMETHOD.


  METHOD constructor.

    TRY.
        DATA(flight_raw) = flights_buffer[ carrier_id = i_carrier_id
                                          connection_id = i_connection_id
                                          flight_date = i_flight_date ].

      CATCH cx_sy_itab_line_not_found.
        SELECT SINGLE
          FROM /lrn/passflight
        FIELDS plane_type_id, seats_max, seats_occupied,
                seats_max - seats_occupied AS seats_free, "añadir cálculo de plazas libres
                price, currency_code
         WHERE carrier_id    = @i_carrier_id
           AND connection_id = @i_connection_id
           AND flight_date   = @i_flight_date
          INTO CORRESPONDING FIELDS OF @flight_raw .
    ENDTRY.

    IF sy-subrc = 0.
      me->carrier_id    = i_carrier_id.
      me->connection_id = i_connection_id.
      me->flight_date   = i_flight_date.

      planetype = flight_raw-plane_type_id.
      seats_max = flight_raw-seats_max.
      seats_occ = flight_raw-seats_occupied.
*      seats_free = flight_raw-seats_max - flight_raw-seats_occupied.
      seats_free = flight_raw-seats_free. "el cálculo se hace en la BBDD

* convert currencies
      TRY.
          cl_exchange_rates=>convert_to_local_currency(
            EXPORTING
              date              = flight_raw-flight_date
              foreign_amount    = flight_raw-price
              foreign_currency  = flight_raw-currency_code
              local_currency    = currency
            IMPORTING
              local_amount      = me->price
          ).
        CATCH cx_exchange_rates.
          CLEAR price.
      ENDTRY.

* Set connection details
*      SELECT SINGLE
*        FROM /lrn/connection
*      FIELDS airport_from_id, airport_to_id, departure_time, arrival_time
*       WHERE carrier_id    = @carrier_id
*         AND connection_id = @connection_id
*        INTO @connection_details .

      connection_details = CORRESPONDING #( connections_buffer[
                                                 carrier_id    = i_carrier_id
                                                 connection_id = i_connection_id ]
                                           ).

    ENDIF.
  ENDMETHOD.

  METHOD get_connection_details.
    r_result = me->connection_details.
  ENDMETHOD.


  METHOD get_free_seats.
    r_result = me->seats_free.
  ENDMETHOD.

  METHOD get_description.

*    APPEND |Flight { carrier_id } { connection_id } on { flight_date DATE = USER } | &&
*           |from { connection_details-airport_from_id } to { connection_details-airport_to_id } |
*           TO r_result. " sustitúyala por una APPEND de una variable local del tipo STRING

    DATA txt TYPE string.
    txt = 'Flight &carrid& &connid& on &date& from &from& to &to&'(005). "frase completa en un único símbolo de texto  ç
                                                                         "Enlace el literal de texto a un nuevo símbolo de texto
    txt = replace( val = txt sub = '&carrid&' with = carrier_id ).
    "REPLACE = Dentro del texto txt, busca la subcadena &carrid&
    "y sustitúyela por el valor real de carrier_id.
    txt = replace( val = txt sub = '&carrid&' with = carrier_id ).
    txt = replace( val = txt sub = '&connid&' with = connection_id ).
    txt = replace( val = txt sub = '&date&' with = |{ flight_date DATE = USER }| ).
    txt = replace( val = txt sub = '&from&' with = connection_details-airport_from_id ).
    txt = replace( val = txt sub = '&to&' with = connection_details-airport_to_id ).

    APPEND txt TO r_result.


*    APPEND |Planetype:      { planetype  } | TO r_result.
*    APPEND |Maximum Seats:  { seats_max  } | TO r_result.
*    APPEND |Occupied Seats: { seats_occ  } | TO r_result.
*    APPEND |Free Seats:     { seats_free } | TO r_result.
*    APPEND |Ticket Price:   { price CURRENCY = currency } { currency } | TO r_result.
*    APPEND |Duration:       { connection_details-duration } minutes| TO r_result. "Actualización tras ampliar el atributo con duración


     APPEND |{ 'Planetype:'(006) } { planetype } | TO r_result.
     APPEND |{ 'Maximum Seats:'(007) } { seats_max } | TO r_result.
     APPEND |{ 'Occupied Seats:'(008) } { seats_occ } | TO r_result.
     APPEND |{ 'Free Seats:'(009) } { seats_free } | TO r_result.
     APPEND |{ 'Ticket Price:'(010) } { price CURRENCY = currency } { currency } | TO r_result.
     APPEND |{ 'Duration:'(011) } { connection_details-duration } { 'minutes'(012) }| TO r_result.


  ENDMETHOD.

ENDCLASS.

CLASS lcl_cargo_flight DEFINITION .

  PUBLIC SECTION.

    TYPES: BEGIN OF st_connection_details,
             airport_from_id TYPE /dmo/airport_from_id,
             airport_to_id   TYPE /dmo/airport_to_id,
             departure_time  TYPE /dmo/flight_departure_time,
             arrival_time    TYPE /dmo/flight_departure_time,
           END OF st_connection_details.

    TYPES
       tt_flights TYPE STANDARD TABLE OF REF TO lcl_cargo_flight WITH DEFAULT KEY.

* wrong:
*    DATA carrier_id    TYPE /dmo/connection_id    READ-ONLY.
*    DATA connection_id TYPE /dmo/carrier_id       READ-ONLY.
* correct:
    DATA carrier_id    TYPE /dmo/carrier_id       READ-ONLY.
    DATA connection_id TYPE /dmo/connection_id    READ-ONLY.

    DATA flight_date   TYPE /dmo/flight_date      READ-ONLY.

    METHODS constructor
      IMPORTING
        i_carrier_id    TYPE /dmo/carrier_id
        i_connection_id TYPE /dmo/connection_id
        i_flight_date   TYPE /dmo/flight_date.

    METHODS get_connection_details
      RETURNING
        VALUE(r_result) TYPE st_connection_details.

    METHODS
      get_free_capacity
        RETURNING
          VALUE(r_result) TYPE /lrn/plane_actual_load.

    METHODS get_description
      RETURNING
        VALUE(r_result) TYPE string_table.

    CLASS-METHODS
      get_flights_by_carrier
        IMPORTING
          i_carrier_id    TYPE /dmo/carrier_id
        RETURNING
          VALUE(r_result) TYPE tt_flights.

  PROTECTED SECTION.
  PRIVATE SECTION.

    TYPES: BEGIN OF st_flights_buffer,
             carrier_id      TYPE /dmo/carrier_id,
             connection_id   TYPE /dmo/connection_id,
             flight_date     TYPE /dmo/flight_date,
             plane_type_id   TYPE /dmo/plane_type_id,
             maximum_load    TYPE /lrn/plane_maximum_load,
             actual_load     TYPE /lrn/plane_actual_load,
             load_unit       TYPE /lrn/plane_weight_unit,
             airport_from_id TYPE /dmo/airport_from_id,
             airport_to_id   TYPE /dmo/airport_to_id,
             departure_time  TYPE /dmo/flight_departure_time,
             arrival_time    TYPE /dmo/flight_arrival_time,
           END OF st_flights_buffer.

    TYPES tt_flights_buffer TYPE HASHED TABLE OF st_flights_buffer
                            WITH UNIQUE KEY carrier_id connection_id flight_date.

    DATA connection_details TYPE st_connection_details.

    DATA planetype TYPE /dmo/plane_type_id.

    DATA maximum_load TYPE /lrn/plane_maximum_load.
    DATA actual_load TYPE /lrn/plane_actual_load.
    DATA load_unit    TYPE /lrn/plane_weight_unit.

    CLASS-DATA flights_buffer TYPE tt_flights_buffer.

ENDCLASS.

CLASS lcl_cargo_flight IMPLEMENTATION.

  METHOD get_flights_by_carrier.

    SELECT
      FROM /lrn/cargoflight
    FIELDS carrier_id, connection_id, flight_date,
           plane_type_id, maximum_load, actual_load, load_unit,
           airport_from_id, airport_to_id, departure_time, arrival_time
     WHERE carrier_id    = @i_carrier_id
      INTO CORRESPONDING FIELDS OF TABLE @flights_buffer.

    LOOP AT flights_buffer INTO DATA(flight).
      APPEND NEW lcl_cargo_flight( i_carrier_id    = flight-carrier_id
                                   i_connection_id = flight-connection_id
                                   i_flight_date   = flight-flight_date )
              TO r_result.

    ENDLOOP.
  ENDMETHOD.

  METHOD constructor.

    " Read buffer
    TRY.
        DATA(flight_raw) = flights_buffer[ carrier_id    = i_carrier_id
                                           connection_id = i_connection_id
                                           flight_date   = i_flight_date ].

      CATCH cx_sy_itab_line_not_found.
        " Read from database if data not found in buffer
        SELECT SINGLE
          FROM /lrn/cargoflight
        FIELDS plane_type_id, maximum_load, actual_load, load_unit,
               airport_from_id, airport_to_id, departure_time, arrival_time
         WHERE carrier_id    = @i_carrier_id
           AND connection_id = @i_connection_id
           AND flight_date   = @i_flight_date
          INTO CORRESPONDING FIELDS OF @flight_raw.
    ENDTRY.

*    carrier_id    =  EXACT #( i_carrier_id ).
    carrier_id    =  i_carrier_id .
*    connection_id =  EXACT #( i_connection_id ).
    connection_id =  i_connection_id .
    flight_date   = i_flight_date.

    planetype = flight_raw-plane_type_id.
    maximum_load = flight_raw-maximum_load.
    actual_load = flight_raw-actual_load.
    load_unit = flight_raw-load_unit.

    connection_details = CORRESPONDING #( flight_raw ).

  ENDMETHOD.


  METHOD get_connection_details.
    r_result = me->connection_details.
  ENDMETHOD.


  METHOD get_free_capacity.
    r_result = maximum_load - actual_load.
  ENDMETHOD.

  METHOD get_description.

    APPEND |Flight { carrier_id } { connection_id } on { flight_date DATE = USER } | &&
           |from { connection_details-airport_from_id } to { connection_details-airport_to_id } |
           TO r_result.
    APPEND |Planetype:     { planetype } |                         TO r_result.
    APPEND |Maximum Load:  { maximum_load         } { load_unit }| TO r_result.
    APPEND |Free Capacity: { get_free_capacity( ) } { load_unit }| TO r_result.

  ENDMETHOD.

ENDCLASS.

CLASS lcl_carrier DEFINITION .

  PUBLIC SECTION.

*    TYPES t_output TYPE c LENGTH 40.
    TYPES t_output TYPE string.

    TYPES tt_output TYPE STANDARD TABLE OF t_output
                    WITH NON-UNIQUE DEFAULT KEY.

    DATA carrier_id TYPE /dmo/carrier_id READ-ONLY.

    METHODS constructor
      IMPORTING
                i_carrier_id TYPE /dmo/carrier_id
      RAISING   cx_abap_invalid_value.

    METHODS get_output RETURNING VALUE(r_result) TYPE tt_output.

    METHODS find_passenger_flight
      IMPORTING
        i_airport_from_id TYPE /dmo/airport_from_id
        i_airport_to_id   TYPE /dmo/airport_to_id
        i_from_date       TYPE /dmo/flight_date
        i_seats           TYPE i
      EXPORTING
        e_flight          TYPE REF TO lcl_passenger_flight
        e_days_later      TYPE i.

    METHODS find_cargo_flight
      IMPORTING
        i_airport_from_id TYPE /dmo/airport_from_id
        i_airport_to_id   TYPE /dmo/airport_to_id
        i_from_date       TYPE /dmo/flight_date
        i_cargo           TYPE /lrn/plane_actual_load
      EXPORTING
        e_flight          TYPE REF TO lcl_cargo_flight
        e_days_later      TYPE i.

  PROTECTED SECTION.
  PRIVATE SECTION.

    DATA name          TYPE string.
    DATA currency_code TYPE /dmo/currency_code ##NEEDED.

    DATA passenger_flights TYPE lcl_passenger_flight=>tt_flights.

    DATA cargo_flights TYPE lcl_cargo_flight=>tt_flights.

    METHODS get_average_free_seats
      RETURNING VALUE(r_result) TYPE i.

ENDCLASS.

CLASS lcl_carrier IMPLEMENTATION.

  METHOD constructor.

    me->carrier_id = i_carrier_id.

    SELECT SINGLE
      FROM /lrn/carrier
*    FIELDS name, currency_code ""ahora la concatenación se hace en select BD antes en ABAP
    FIELDS concat_with_space( carrier_id, name, 1 ), currency_code
     WHERE carrier_id = @i_carrier_id
     INTO ( @me->name, @me->currency_code ).

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE cx_abap_invalid_value.
    ENDIF.

*    name = carrier_id && ` ` && name. "ahora la concatenación se hace en select concat_with_space( carrier_id, name, 1 )

    passenger_flights =
        lcl_passenger_flight=>get_flights_by_carrier(
              i_carrier_id    = i_carrier_id ).

    cargo_flights =
        lcl_cargo_flight=>get_flights_by_carrier(
              i_carrier_id    = i_carrier_id ).

  ENDMETHOD.

  METHOD get_output.

*    APPEND |Carrier Name:       { me->name } | TO r_result. ""Sustituir texto literal por literal incrustado
*    APPEND |Passenger Flights:  { lines( passenger_flights ) } | TO r_result.
*    APPEND |Average free seats: { get_average_free_seats(  ) } | TO r_result.
*    APPEND |Cargo Flights:      { lines( cargo_flights     ) } | TO r_result.
    APPEND |{ 'Carrier Name:'(001) } { me->name }                   | TO r_result. "texto literal incrustado +
                               "Convertir el literal en símbolo de texto(001)
    APPEND |{ 'Passenger Flights:'(002) } { lines( passenger_flights ) } | TO r_result.
    APPEND |{ 'Average free seats:'(003) } { get_average_free_seats( ) } | TO r_result.
    APPEND |{ 'Cargo Flights:'(004) } { lines( cargo_flights ) }         | TO r_result.

  ENDMETHOD.

  METHOD find_cargo_flight.

    e_days_later = 99999999.

    LOOP AT me->cargo_flights INTO DATA(flight)
        WHERE table_line->flight_date >= i_from_date.

      DATA(connection_details) = flight->get_connection_details(  ).

      IF connection_details-airport_from_id = i_airport_from_id
       AND connection_details-airport_to_id = i_airport_to_id
       AND flight->get_free_capacity(  ) >= i_cargo.

*        DATA(days_later) =  i_from_date - flight->flight_date.
        DATA(days_later) =   flight->flight_date - i_from_date .

        IF days_later < e_days_later. "earlier than previous one?
          e_flight = flight.
          e_days_later = days_later.
        ENDIF.
      ENDIF.

    ENDLOOP.
  ENDMETHOD.

  METHOD find_passenger_flight.

    e_days_later = 99999999.

    LOOP AT me->passenger_flights INTO DATA(flight)
         WHERE table_line->flight_date >= i_from_date.

      DATA(connection_details) = flight->get_connection_details(  ).

      IF connection_details-airport_from_id = i_airport_from_id
       AND connection_details-airport_to_id = i_airport_to_id
       AND flight->get_free_seats( ) >= i_seats.
        DATA(days_later) = flight->flight_date - i_from_date.

        IF days_later < e_days_later. "earlier than previous one?
          e_flight = flight.
          e_days_later = days_later.
        ENDIF.
      ENDIF.

    ENDLOOP.

  ENDMETHOD.

  METHOD get_average_free_seats.

    DATA total TYPE i.

    LOOP AT passenger_flights INTO DATA(flight).

      total = total + flight->get_free_seats( ).

    ENDLOOP.

    r_result = total / lines( passenger_flights ).

  ENDMETHOD.

ENDCLASS.
