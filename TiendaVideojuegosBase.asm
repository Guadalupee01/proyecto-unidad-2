; =============================================================================
; PROYECTO: Sistema de Ventas e Inventario (Tienda de Videojuegos)
; ARQUITECTURA: x86 32-bits (MASM) con libreria Irvine32
; RESTRICCIONES CUMPLIDAS:
;   - Solo ReadString y WriteString para E/S de datos y numeros.
;   - Prohibido: ReadDec, ReadInt, ParseDecimal32, WriteDec, WriteHex.
;   - Precios internos en centavos enteros (1 a 999999 centavos).
;   - Recorridos de arreglos de estructuras indexados con ESI.
;   - Pila equilibrada y documentacion completa en cada procedimiento.
; =============================================================================

INCLUDE Irvine32.inc

; -----------------------------------------------------------------------------
; DEFINICION DE ESTRUCTURA Y CONSTANTES
; -----------------------------------------------------------------------------
PRODUCTO STRUCT
    codigo      BYTE 8 DUP(0)       ; 7 chars (ABC-123) + 1 nulo (Offset 0)
    nombre      BYTE 26 DUP(0)      ; 1 a 25 chars + 1 nulo      (Offset 8)
    align_pad   BYTE 2 DUP(0)       ; Padding para alinear DWORD (Offset 34)
    precio      DWORD 0             ; En centavos: 1 a 999999    (Offset 36)
    existencia  DWORD 0             ; De 0 a 100 unidades        (Offset 40)
    vendidos    DWORD 0             ; Acumulado de ventas        (Offset 44)
PRODUCTO ENDS                       ; Tamano exacto = 48 bytes

MAX_PROD        EQU 10
TAM_PROD        EQU TYPE PRODUCTO   ; 48 bytes
ARCHIVO_BYTES   EQU 484             ; 4 bytes (contador) + 480 bytes (10 productos)

.data
; --- Almacenamiento Principal del Catalogo ---
numProductos    DWORD 0
catalogo        PRODUCTO MAX_PROD DUP(<>)

; --- Buffer Temporal para Validacion de Carga de Archivo ---
tempNumProd     DWORD 0
tempCatalogo    PRODUCTO MAX_PROD DUP(<>)

; --- Variables de Estado de la Sesion ---
ingresosSesion  DWORD 0             ; Acumulado en centavos
cambiosSinG     DWORD 0             ; Bandera: 0 = guardado, 1 = cambios pendientes
nombreArchivo   BYTE "inventario.dat", 0
manejadorArch   DWORD ?

; --- Buffers de Captura y Conversion Propia ---
bufEntrada      BYTE 64 DUP(0)
bufNumero       BYTE 32 DUP(0)
bufMoneda       BYTE 32 DUP(0)

; --- Variables Auxiliares de Trabajo ---
auxCodigo       BYTE 8 DUP(0)
auxNombre       BYTE 26 DUP(0)
auxPrecio       DWORD 0
auxExistencia   DWORD 0
auxCantidad     DWORD 0

; --- Textos de Interfaz y Menus ---
strTitulo       BYTE 0Dh, 0Ah, "==========================================================", 0Dh, 0Ah
                BYTE "     SISTEMA DE VENTAS E INVENTARIO - VIDEOJUEGOS         ", 0Dh, 0Ah
                BYTE "==========================================================", 0Dh, 0Ah, 0
strMenu         BYTE "1. Registrar nuevo producto", 0Dh, 0Ah
                BYTE "2. Mostrar inventario completo", 0Dh, 0Ah
                BYTE "3. Buscar producto por codigo", 0Dh, 0Ah
                BYTE "4. Recibir mercancia (Entradas)", 0Dh, 0Ah
                BYTE "5. Realizar venta", 0Dh, 0Ah
                BYTE "6. Mostrar resumen y Regla de Negocio", 0Dh, 0Ah
                BYTE "7. Guardar catalogo en archivo", 0Dh, 0Ah
                BYTE "8. Cargar catalogo desde archivo", 0Dh, 0Ah
                BYTE "9. Salir", 0Dh, 0Ah
                BYTE "Seleccione una opcion (1-9): ", 0

; --- Mensajes de Solicitud (Prompts) ---
msgPedirCod     BYTE "Ingrese codigo (Formato ABC-123): ", 0
msgPedirNom     BYTE "Ingrese nombre del videojuego (1-25 caracteres): ", 0
msgPedirPre     BYTE "Ingrese precio en pesos (0.01 a 9999.99): ", 0
msgPedirExi     BYTE "Ingrese existencia inicial (0 a 100): ", 0
msgPedirCantE   BYTE "Ingrese cantidad a recibir (> 0): ", 0
msgPedirCantV   BYTE "Ingrese cantidad a vender (> 0): ", 0
msgAvisoSalir   BYTE 0Dh, 0Ah, "ADVERTENCIA: Hay cambios sin guardar en el catalogo.", 0Dh, 0Ah
                BYTE "Desea salir de todas formas? (S/N): ", 0

; --- Mensajes de Error y Validacion ---
errOpcion       BYTE ">> ERROR: Opcion invalida. Intente de nuevo.", 0Dh, 0Ah, 0
errLleno        BYTE ">> ERROR: El catalogo ya alcanzo el limite de 10 productos.", 0Dh, 0Ah, 0
errCodFormato   BYTE ">> ERROR: Formato invalido. Use 3 mayusculas, guion y 3 digitos (ej. JUE-001).", 0Dh, 0Ah, 0
errCodDuplicado BYTE ">> ERROR: El codigo ingresado ya existe en el catalogo.", 0Dh, 0Ah, 0
errNoEncontrado BYTE ">> ERROR: Producto no encontrado en el catalogo.", 0Dh, 0Ah, 0
errNomVacio     BYTE ">> ERROR: El nombre debe tener entre 1 y 25 caracteres.", 0Dh, 0Ah, 0
errPrecio       BYTE ">> ERROR: Precio invalido. Rango: 0.01 a 9999.99 (sin simbolos ni comas).", 0Dh, 0Ah, 0
errExistencia   BYTE ">> ERROR: La existencia debe ser un entero entre 0 y 100.", 0Dh, 0Ah, 0
errCantidad     BYTE ">> ERROR: La cantidad debe ser un entero mayor que 0.", 0Dh, 0Ah, 0
errExcesoStock  BYTE ">> ERROR: La entrada supera el limite maximo de 100 unidades.", 0Dh, 0Ah, 0
errSinStock     BYTE ">> ERROR: Existencias insuficientes para realizar la venta.", 0Dh, 0Ah, 0
errArchivoG     BYTE ">> ERROR: No se pudo crear o escribir el archivo de inventario.", 0Dh, 0Ah, 0
errArchivoC     BYTE ">> ERROR: Archivo inexistente, tamano incorrecto o datos corruptos.", 0Dh, 0Ah, 0

; --- Mensajes de Exito y Formatos de Salida ---
okAlta          BYTE ">> Producto registrado exitosamente.", 0Dh, 0Ah, 0
okEntrada       BYTE ">> Mercancia recibida. Nueva existencia: ", 0
okGuardado      BYTE ">> Catalogo guardado correctamente en 'inventario.dat'.", 0Dh, 0Ah, 0
okCargado       BYTE ">> Catalogo verificado y cargado exitosamente.", 0Dh, 0Ah, 0
msgVacio        BYTE ">> El inventario se encuentra vacio actualmente.", 0Dh, 0Ah, 0

lblCabecera     BYTE 0Dh, 0Ah, "CODIGO  | NOMBRE                    | PRECIO          | STOCK | VENDIDOS", 0Dh, 0Ah
                BYTE "------------------------------------------------------------------------", 0Dh, 0Ah, 0
lblSep          BYTE " | ", 0
lblMXN          BYTE " MXN", 0
lblSalto        BYTE 0Dh, 0Ah, 0

; --- Textos de Ticket de Venta y Resumen ---
lblTicket       BYTE 0Dh, 0Ah, "--- DETALLE DE VENTA ---", 0Dh, 0Ah, 0
lblSubtotal     BYTE "Importe Base:      $", 0
lblDescuento    BYTE "Descuento (10%):  -$", 0
lblTotalVenta   BYTE "Total a Pagar:     $", 0
lblStockRest    BYTE "Stock Restante:     ", 0

lblResTitulo    BYTE 0Dh, 0Ah, "=== RESUMEN DEL SISTEMA Y REGLA DE NEGOCIO ===", 0Dh, 0Ah, 0
lblResUnidades  BYTE "Total Unidades Disponibles:  ", 0
lblResValor     BYTE "Valor Total del Inventario:  $", 0
lblResIngresos  BYTE "Ingresos de la Sesion:       $", 0
lblResRegla1    BYTE 0Dh, 0Ah, "[REGLA DE NEGOCIO ACTIVA]:", 0Dh, 0Ah
                BYTE "1. Mayoreo: 10% de descuento en ventas de 5 o mas unidades (sin fracciones de centavo).", 0Dh, 0Ah
                BYTE "2. Alerta de Stock Critico (menos de 5 unidades) y Producto Mas Vendido:", 0Dh, 0Ah, 0
lblMasVendido   BYTE "   -> Producto mas vendido: ", 0
lblSinVentas    BYTE "   -> Aun no se registran ventas en el catalogo.", 0Dh, 0Ah, 0
lblAlertaStock  BYTE "   -> [ALERTA STOCK BAJO]: ", 0
lblUnidades     BYTE " unidades", 0Dh, 0Ah, 0

.code
; =============================================================================
; PROCEDIMIENTO PRINCIPAL (main)
; =============================================================================
main PROC
CicloMenu:
    mov edx, OFFSET strTitulo
    call WriteString
    mov edx, OFFSET strMenu
    call WriteString

    ; Capturar opcion de menu con ReadString
    mov edx, OFFSET bufEntrada
    mov ecx, SIZEOF bufEntrada - 1
    call ReadString

    ; Validar que sea exactamente 1 caracter entre '1' y '9'
    cmp eax, 1
    jne OpcionInvalida
    mov al, bufEntrada[0]
    cmp al, '1'
    jb OpcionInvalida
    cmp al, '9'
    ja OpcionInvalida

    call Crlf

    ; Enrutador de opciones
    cmp al, '1'
    je OpRegistrar
    cmp al, '2'
    je OpMostrar
    cmp al, '3'
    je OpBuscar
    cmp al, '4'
    je OpRecibir
    cmp al, '5'
    je OpVender
    cmp al, '6'
    je OpResumen
    cmp al, '7'
    je OpGuardar
    cmp al, '8'
    je OpCargar
    cmp al, '9'
    je OpSalir

OpcionInvalida:
    mov edx, OFFSET errOpcion
    call WriteString
    jmp CicloMenu

OpRegistrar:
    call RegistrarProducto
    jmp CicloMenu
OpMostrar:
    call MostrarInventario
    jmp CicloMenu
OpBuscar:
    call ConsultarPorCodigo
    jmp CicloMenu
OpRecibir:
    call RecibirMercancia
    jmp CicloMenu
OpVender:
    call RealizarVenta
    jmp CicloMenu
OpResumen:
    call MostrarResumen
    jmp CicloMenu
OpGuardar:
    call GuardarArchivo
    jmp CicloMenu
OpCargar:
    call CargarArchivo
    jmp CicloMenu

OpSalir:
    cmp cambiosSinG, 0
    je FinPrograma
PedirConfirmacion:
    mov edx, OFFSET msgAvisoSalir
    call WriteString
    mov edx, OFFSET bufEntrada
    mov ecx, SIZEOF bufEntrada - 1
    call ReadString
    cmp eax, 1
    jne PedirConfirmacion
    mov al, bufEntrada[0]
    cmp al, 'S'
    je FinPrograma
    cmp al, 's'
    je FinPrograma
    cmp al, 'N'
    je CicloMenu
    cmp al, 'n'
    je CicloMenu
    jmp PedirConfirmacion

FinPrograma:
    exit
main ENDP

; =============================================================================
; 1. PROCEDIMIENTOS DE CONVERSION Y VALIDACION PROPIA (SIN FUNCIONES DE IRVINE)
; =============================================================================

; -----------------------------------------------------------------------------
; ValidarFormatoCodigo
; Verifica que una cadena cumpla exactamente el patron ABC-123 (7 caracteres).
; Entradas: EDX = Offset de la cadena a evaluar.
; Salidas:  EAX = 1 si es valido, 0 si es invalido.
; Registros modificados: Ninguno (preserva con PUSH/POP).
; -----------------------------------------------------------------------------
ValidarFormatoCodigo PROC
    push esi
    push ecx
    mov esi, edx

    ; 1. Revisar 3 letras mayusculas (posiciones 0, 1, 2)
    mov ecx, 3
RevLetras:
    mov al, [esi]
    cmp al, 'A'
    jb FormatoInvalido
    cmp al, 'Z'
    ja FormatoInvalido
    inc esi
    loop RevLetras

    ; 2. Revisar guion en posicion 3
    mov al, [esi]
    cmp al, '-'
    jne FormatoInvalido
    inc esi

    ; 3. Revisar 3 digitos (posiciones 4, 5, 6)
    mov ecx, 3
RevDigitos:
    mov al, [esi]
    cmp al, '0'
    jb FormatoInvalido
    cmp al, '9'
    ja FormatoInvalido
    inc esi
    loop RevDigitos

    ; 4. Revisar fin de cadena (posicion 7 debe ser 0)
    mov al, [esi]
    cmp al, 0
    jne FormatoInvalido

    mov eax, 1
    jmp FinValCod

FormatoInvalido:
    mov eax, 0
FinValCod:
    pop ecx
    pop esi
    ret
ValidarFormatoCodigo ENDP

; -----------------------------------------------------------------------------
; CadenaAEntero
; Convierte una cadena ASCII de digitos en un entero sin signo de 32 bits.
; Rechaza cadenas vacias, signos, espacios o desbordamientos (> 100000).
; Entradas: EDX = Offset de la cadena terminada en 0.
; Salidas:  EAX = Valor convertido, EBX = 1 si exito, 0 si error.
; Registros modificados: EAX, EBX (preserva ESI, ECX, EDX).
; -----------------------------------------------------------------------------
CadenaAEntero PROC
    push esi
    push ecx
    push edx

    mov esi, edx
    xor eax, eax            ; Acumulador = 0
    mov bl, [esi]
    cmp bl, 0               ; Rechazar cadena vacia
    je ErrorEntero

CicloEntero:
    movzx ecx, BYTE PTR [esi]
    cmp cl, 0
    je ExitoEntero
    cmp cl, '0'
    jb ErrorEntero
    cmp cl, '9'
    ja ErrorEntero

    sub cl, '0'
    mov edx, 10
    mul edx                 ; EAX = EAX * 10
    jc ErrorEntero          ; Desbordamiento de 32 bits
    add eax, ecx
    jc ErrorEntero
    cmp eax, 100000         ; Tope de seguridad contra desbordamientos logicos
    ja ErrorEntero

    inc esi
    jmp CicloEntero

ExitoEntero:
    mov ebx, 1
    jmp FinCadEnt
ErrorEntero:
    xor eax, eax
    xor ebx, ebx
FinCadEnt:
    pop edx
    pop ecx
    pop esi
    ret
CadenaAEntero ENDP

; -----------------------------------------------------------------------------
; CadenaAPrecioCentavos
; Convierte una cadena en formato "185", "185.5" o "185.50" a centavos enteros.
; Rango permitido: 1 ($0.01) a 999999 ($9999.99).
; Entradas: EDX = Offset de la cadena.
; Salidas:  EAX = Precio en centavos, EBX = 1 si valido, 0 si error.
; Registros modificados: EAX, EBX (preserva ESI, ECX, EDX, EDI).
; -----------------------------------------------------------------------------
CadenaAPrecioCentavos PROC
    push esi
    push ecx
    push edx
    push edi

    mov esi, edx
    xor eax, eax            ; Acumulador de parte entera (pesos)
    xor edi, edi            ; Contador de digitos enteros

    mov bl, [esi]
    cmp bl, 0
    je PrecioInvalido       ; Rechazar vacio

    ; --- Fase 1: Parte Entera ---
CicloPesos:
    movzx ecx, BYTE PTR [esi]
    cmp cl, 0
    je SinDecimales
    cmp cl, '.'
    je ProcesarPunto
    cmp cl, '0'
    jb PrecioInvalido
    cmp cl, '9'
    ja PrecioInvalido

    inc edi
    cmp edi, 4              ; Maximo 4 digitos enteros (9999)
    ja PrecioInvalido

    sub cl, '0'
    mov edx, 10
    mul edx
    add eax, ecx
    inc esi
    jmp CicloPesos

SinDecimales:
    cmp edi, 0
    je PrecioInvalido
    mov edx, 100
    mul edx                 ; Convertir pesos a centavos (pesos * 100)
    jmp VerificarRangoPrecio

    ; --- Fase 2: Parte Decimal ---
ProcesarPunto:
    cmp edi, 0              ; Debe haber al menos un digito antes del punto
    je PrecioInvalido
    inc esi                 ; Avanzar despues del '.'

    ; Primer digito decimal (obligatorio si hay punto)
    movzx ecx, BYTE PTR [esi]
    cmp cl, '0'
    jb PrecioInvalido
    cmp cl, '9'
    ja PrecioInvalido
    sub cl, '0'
    mov edi, ecx            ; EDI guarda decimas
    inc esi

    ; Segundo digito decimal (opcional)
    movzx ecx, BYTE PTR [esi]
    cmp cl, 0
    je UnSoloDecimal
    cmp cl, '0'
    jb PrecioInvalido
    cmp cl, '9'
    ja PrecioInvalido
    sub cl, '0'             ; ECX guarda centesimas
    inc esi

    ; Despues del segundo decimal debe terminar la cadena
    cmp BYTE PTR [esi], 0
    jne PrecioInvalido

    ; Calcular: (Pesos * 100) + (Decimas * 10) + Centesimas
    mov edx, 100
    mul edx
    imul edi, 10
    add eax, edi
    add eax, ecx
    jmp VerificarRangoPrecio

UnSoloDecimal:
    mov edx, 100
    mul edx
    imul edi, 10
    add eax, edi

VerificarRangoPrecio:
    cmp eax, 1              ; Minimo $0.01 (1 centavo)
    jb PrecioInvalido
    cmp eax, 999999         ; Maximo $9999.99 (999999 centavos)
    ja PrecioInvalido

    mov ebx, 1
    jmp FinCadPrecio

PrecioInvalido:
    xor eax, eax
    xor ebx, ebx
FinCadPrecio:
    pop edi
    pop edx
    pop ecx
    pop esi
    ret
CadenaAPrecioCentavos ENDP

; -----------------------------------------------------------------------------
; ImprimirEntero
; Convierte un entero sin signo en EAX a cadena ASCII mediante divisiones
; sucesivas entre 10 y lo imprime con WriteString.
; Entradas: EAX = Numero entero a mostrar.
; Salidas:  Impresion en consola.
; Registros modificados: Ninguno (usa PUSHAD/POPAD).
; -----------------------------------------------------------------------------
ImprimirEntero PROC
    pushad
    mov edi, OFFSET bufNumero + 30
    mov BYTE PTR [edi], 0   ; Terminador nulo al final del buffer
    mov ebx, 10

    cmp eax, 0
    jne CicloDivEnt
    dec edi
    mov BYTE PTR [edi], '0'
    jmp MostrarEnt

CicloDivEnt:
    cmp eax, 0
    je MostrarEnt
    xor edx, edx
    div ebx                 ; EAX = cociente, EDX = residuo (0-9)
    add dl, '0'
    dec edi
    mov [edi], dl
    jmp CicloDivEnt

MostrarEnt:
    mov edx, edi
    call WriteString
    popad
    ret
ImprimirEntero ENDP

; -----------------------------------------------------------------------------
; ImprimirMonedaMXN
; Recibe un monto en centavos en EAX y lo muestra con formato "XXXX.XX MXN"
; usando divisiones enteras y WriteString.
; Entradas: EAX = Importe en centavos enteros.
; Salidas:  Impresion formateada en pantalla.
; Registros modificados: Ninguno (usa PUSHAD/POPAD).
; -----------------------------------------------------------------------------
ImprimirMonedaMXN PROC
    pushad
    xor edx, edx
    mov ebx, 100
    div ebx                 ; EAX = Pesos enteros, EDX = Centavos (00 a 99)

    push edx                ; Guardar centavos en la pila
    call ImprimirEntero     ; Imprime la parte entera (pesos)

    ; Imprimir punto decimal y los dos digitos de centavos
    pop eax                 ; Recuperar centavos en EAX
    xor edx, edx
    mov ebx, 10
    div ebx                 ; AL = decimas, DL = centesimas

    add al, '0'
    add dl, '0'
    mov bufMoneda[0], '.'
    mov bufMoneda[1], al
    mov bufMoneda[2], dl
    mov bufMoneda[3], 0

    mov edx, OFFSET bufMoneda
    call WriteString
    mov edx, OFFSET lblMXN
    call WriteString

    popad
    ret
ImprimirMonedaMXN ENDP

; =============================================================================
; 2. PROCEDIMIENTOS DE BUSQUEDA Y RECORRIDO CON ESI
; =============================================================================

; -----------------------------------------------------------------------------
; CompararCadenas
; Compara dos cadenas terminadas en nulo caracter por caracter.
; Entradas: ESI = Cadena 1, EDI = Cadena 2.
; Salidas:  EAX = 1 si son identicas, 0 si son diferentes.
; Registros modificados: EAX (preserva ESI, EDI, EBX).
; -----------------------------------------------------------------------------
CompararCadenas PROC
    push esi
    push edi
    push ebx
CicloComp:
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne CadDiferentes
    cmp al, 0
    je CadIguales
    inc esi
    inc edi
    jmp CicloComp
CadIguales:
    mov eax, 1
    jmp FinComp
CadDiferentes:
    xor eax, eax
FinComp:
    pop ebx
    pop edi
    pop esi
    ret
CompararCadenas ENDP

; -----------------------------------------------------------------------------
; CopiarCadena
; Copia una cadena terminada en nulo de ESI hacia EDI.
; Entradas: ESI = Origen, EDI = Destino.
; Salidas:  Memoria destino actualizada.
; Registros modificados: Ninguno.
; -----------------------------------------------------------------------------
CopiarCadena PROC
    push esi
    push edi
    push eax
CicloCopia:
    mov al, [esi]
    mov [edi], al
    cmp al, 0
    je FinCopia
    inc esi
    inc edi
    jmp CicloCopia
FinCopia:
    pop eax
    pop edi
    pop esi
    ret
CopiarCadena ENDP

; -----------------------------------------------------------------------------
; BuscarProductoPorCodigo
; Recorre el catalogo utilizando ESI para localizar un producto por su codigo.
; Entradas: EDX = Offset del codigo buscado.
; Salidas:  EAX = 1 si lo encontro (ESI apunta al registro del producto),
;           EAX = 0 si no existe.
; Registros modificados: EAX, ESI (preserva ECX, EDI).
; -----------------------------------------------------------------------------
BuscarProductoPorCodigo PROC
    push ecx
    push edi

    mov ecx, numProductos
    cmp ecx, 0
    je NoEncontrado

    mov esi, OFFSET catalogo    ; ESI apunta al inicio del arreglo de estructuras
    mov edi, edx                ; EDI apunta al codigo buscado

CicloBusquedaESI:
    call CompararCadenas        ; Compara [ESI] (campo codigo en offset 0) con [EDI]
    cmp eax, 1
    je Encontrado
    add esi, TAM_PROD           ; Avanzar ESI al siguiente producto (+48 bytes)
    loop CicloBusquedaESI

NoEncontrado:
    xor eax, eax
    jmp FinBusqueda
Encontrado:
    mov eax, 1                  ; ESI conserva la direccion exacta del producto
FinBusqueda:
    pop edi
    pop ecx
    ret
BuscarProductoPorCodigo ENDP

; -----------------------------------------------------------------------------
; ImprimirFilaProducto
; Muestra en consola los datos del producto apuntado por ESI.
; Entradas: ESI = Direccion del registro PRODUCTO.
; Salidas:  Impresion en consola.
; Registros modificados: Ninguno (usa PUSHAD/POPAD).
; -----------------------------------------------------------------------------
ImprimirFilaProducto PROC
    pushad
    ; 1. Codigo
    mov edx, esi
    call WriteString
    mov edx, OFFSET lblSep
    call WriteString

    ; 2. Nombre (rellenado a 25 espacios para alinear tabla)
    lea edx, [esi + PRODUCTO.nombre]
    call WriteString
    mov edi, edx
    xor ecx, ecx
ContarLargoNom:
    cmp BYTE PTR [edi], 0
    je RellenarEspacios
    inc edi
    inc ecx
    jmp ContarLargoNom
RellenarEspacios:
    mov eax, 25
    sub eax, ecx
    mov ecx, eax
    mov al, ' '
CicloPad:
    cmp ecx, 0
    jle FinPad
    call WriteChar
    dec ecx
    jmp CicloPad
FinPad:
    mov edx, OFFSET lblSep
    call WriteString

    ; 3. Precio en MXN
    mov eax, [esi + PRODUCTO.precio]
    call ImprimirMonedaMXN
    mov edx, OFFSET lblSep
    call WriteString

    ; 4. Existencia
    mov eax, [esi + PRODUCTO.existencia]
    call ImprimirEntero
    mov edx, OFFSET lblSep
    call WriteString

    ; 5. Unidades Vendidas
    mov eax, [esi + PRODUCTO.vendidos]
    call ImprimirEntero
    call Crlf

    popad
    ret
ImprimirFilaProducto ENDP

; =============================================================================
; 3. FUNCIONES OBLIGATORIAS DEL NEGOCIO
; =============================================================================

; -----------------------------------------------------------------------------
; 1A. RegistrarProducto
; Captura y valida codigo unico, nombre, precio y existencia inicial.
; Entradas: Ninguna. Salidas: Catalogo actualizado.
; -----------------------------------------------------------------------------
RegistrarProducto PROC
    pushad
    mov eax, numProductos
    cmp eax, MAX_PROD
    jb PedirDatosCodigo
    mov edx, OFFSET errLleno
    call WriteString
    jmp FinRegistrar

    ; --- Paso 1: Capturar y validar Codigo ---
PedirDatosCodigo:
    mov edx, OFFSET msgPedirCod
    call WriteString
    mov edx, OFFSET bufEntrada
    mov ecx, SIZEOF bufEntrada - 1
    call ReadString

    mov edx, OFFSET bufEntrada
    call ValidarFormatoCodigo
    cmp eax, 1
    je RevisarDuplicado
    mov edx, OFFSET errCodFormato
    call WriteString
    jmp PedirDatosCodigo

RevisarDuplicado:
    mov edx, OFFSET bufEntrada
    call BuscarProductoPorCodigo
    cmp eax, 0
    je GuardarCodigoTemp
    mov edx, OFFSET errCodDuplicado
    call WriteString
    jmp PedirDatosCodigo

GuardarCodigoTemp:
    mov esi, OFFSET bufEntrada
    mov edi, OFFSET auxCodigo
    call CopiarCadena

    ; --- Paso 2: Capturar y validar Nombre (1 a 25 chars) ---
PedirDatosNombre:
    mov edx, OFFSET msgPedirNom
    call WriteString
    mov edx, OFFSET bufEntrada
    mov ecx, SIZEOF bufEntrada - 1
    call ReadString

    cmp eax, 1
    jb ErrorNom
    cmp eax, 25
    ja ErrorNom
    ; Verificar que no sean puros espacios
    cmp BYTE PTR bufEntrada[0], ' '
    je ErrorNom

    mov esi, OFFSET bufEntrada
    mov edi, OFFSET auxNombre
    call CopiarCadena
    jmp PedirDatosPrecio

ErrorNom:
    mov edx, OFFSET errNomVacio
    call WriteString
    jmp PedirDatosNombre

    ; --- Paso 3: Capturar y validar Precio ---
PedirDatosPrecio:
    mov edx, OFFSET msgPedirPre
    call WriteString
    mov edx, OFFSET bufEntrada
    mov ecx, SIZEOF bufEntrada - 1
    call ReadString

    mov edx, OFFSET bufEntrada
    call CadenaAPrecioCentavos
    cmp ebx, 1
    je GuardarPrecioTemp
    mov edx, OFFSET errPrecio
    call WriteString
    jmp PedirDatosPrecio

GuardarPrecioTemp:
    mov auxPrecio, eax

    ; --- Paso 4: Capturar y validar Existencia (0 a 100) ---
PedirDatosExistencia:
    mov edx, OFFSET msgPedirExi
    call WriteString
    mov edx, OFFSET bufEntrada
    mov ecx, SIZEOF bufEntrada - 1
    call ReadString

    mov edx, OFFSET bufEntrada
    call CadenaAEntero
    cmp ebx, 1
    jne ErrorExi
    cmp eax, 100
    ja ErrorExi
    mov auxExistencia, eax
    jmp InsertarEnCatalogo

ErrorExi:
    mov edx, OFFSET errExistencia
    call WriteString
    jmp PedirDatosExistencia

    ; --- Paso 5: Guardar en el arreglo usando ESI ---
InsertarEnCatalogo:
    mov eax, numProductos
    mov ebx, TAM_PROD
    mul ebx
    mov esi, OFFSET catalogo
    add esi, eax                ; ESI apunta al nuevo slot libre

    ; Copiar codigo
    push esi
    mov edi, esi
    mov esi, OFFSET auxCodigo
    call CopiarCadena
    pop esi

    ; Copiar nombre
    push esi
    lea edi, [esi + PRODUCTO.nombre]
    mov esi, OFFSET auxNombre
    call CopiarCadena
    pop esi

    ; Asignar valores numericos
    mov eax, auxPrecio
    mov [esi + PRODUCTO.precio], eax
    mov eax, auxExistencia
    mov [esi + PRODUCTO.existencia], eax
    mov DWORD PTR [esi + PRODUCTO.vendidos], 0

    inc numProductos
    mov cambiosSinG, 1

    mov edx, OFFSET okAlta
    call WriteString

FinRegistrar:
    popad
    ret
RegistrarProducto ENDP

; -----------------------------------------------------------------------------
; 1B. MostrarInventario
; Recorre el catalogo con ESI e imprime todos los productos registrados.
; -----------------------------------------------------------------------------
MostrarInventario PROC
    pushad
    mov ecx, numProductos
    cmp ecx, 0
    jne ImprimirTabla
    mov edx, OFFSET msgVacio
    call WriteString
    jmp FinMostrar

ImprimirTabla:
    mov edx, OFFSET lblCabecera
    call WriteString
    mov esi, OFFSET catalogo    ; Inicializar puntero ESI al inicio del catalogo

CicloMostrarESI:
    call ImprimirFilaProducto
    add esi, TAM_PROD           ; Avanzar ESI al siguiente registro
    loop CicloMostrarESI

FinMostrar:
    popad
    ret
MostrarInventario ENDP

; -----------------------------------------------------------------------------
; 1C. ConsultarPorCodigo
; Solicita un codigo y muestra el detalle del producto si existe.
; -----------------------------------------------------------------------------
ConsultarPorCodigo PROC
    pushad
    cmp numProductos, 0
    jne PedirCodBusqueda
    mov edx, OFFSET msgVacio
    call WriteString
    jmp FinConsulta

PedirCodBusqueda:
    mov edx, OFFSET msgPedirCod
    call WriteString
    mov edx, OFFSET bufEntrada
    mov ecx, SIZEOF bufEntrada - 1
    call ReadString

    mov edx, OFFSET bufEntrada
    call ValidarFormatoCodigo
    cmp eax, 1
    je EjecutarBusqueda
    mov edx, OFFSET errCodFormato
    call WriteString
    jmp PedirCodBusqueda

EjecutarBusqueda:
    mov edx, OFFSET bufEntrada
    call BuscarProductoPorCodigo
    cmp eax, 1
    je MostrarEncontrado
    mov edx, OFFSET errNoEncontrado
    call WriteString
    jmp FinConsulta

MostrarEncontrado:
    mov edx, OFFSET lblCabecera
    call WriteString
    call ImprimirFilaProducto   ; ESI ya apunta al producto localizado

FinConsulta:
    popad
    ret
ConsultarPorCodigo ENDP

; -----------------------------------------------------------------------------
; 2. RecibirMercancia
; Suma unidades a un producto existente validando que no exceda 100 unidades.
; -----------------------------------------------------------------------------
RecibirMercancia PROC
    pushad
    cmp numProductos, 0
    jne PedirCodEntrada
    mov edx, OFFSET msgVacio
    call WriteString
    jmp FinRecibir

PedirCodEntrada:
    mov edx, OFFSET msgPedirCod
    call WriteString
    mov edx, OFFSET bufEntrada
    mov ecx, SIZEOF bufEntrada - 1
    call ReadString

    mov edx, OFFSET bufEntrada
    call ValidarFormatoCodigo
    cmp eax, 1
    je BuscarProdEntrada
    mov edx, OFFSET errCodFormato
    call WriteString
    jmp PedirCodEntrada

BuscarProdEntrada:
    mov edx, OFFSET bufEntrada
    call BuscarProductoPorCodigo
    cmp eax, 1
    je CapturarCantEntrada
    mov edx, OFFSET errNoEncontrado
    call WriteString
    jmp FinRecibir

CapturarCantEntrada:
    ; ESI apunta al producto encontrado
    mov edx, OFFSET msgPedirCantE
    call WriteString
    mov edx, OFFSET bufEntrada
    mov ecx, SIZEOF bufEntrada - 1
    call ReadString

    mov edx, OFFSET bufEntrada
    call CadenaAEntero
    cmp ebx, 1
    jne ErrorCantE
    cmp eax, 0
    je ErrorCantE

    ; Verificar limite de 100 unidades
    mov ebx, [esi + PRODUCTO.existencia]
    add ebx, eax
    cmp ebx, 100
    ja ErrorTope100

    ; Actualizar existencia
    mov [esi + PRODUCTO.existencia], ebx
    mov cambiosSinG, 1

    mov edx, OFFSET okEntrada
    call WriteString
    mov eax, ebx
    call ImprimirEntero
    call Crlf
    jmp FinRecibir

ErrorCantE:
    mov edx, OFFSET errCantidad
    call WriteString
    jmp CapturarCantEntrada

ErrorTope100:
    mov edx, OFFSET errExcesoStock
    call WriteString
    jmp CapturarCantEntrada

FinRecibir:
    popad
    ret
RecibirMercancia ENDP

; -----------------------------------------------------------------------------
; 3. RealizarVenta
; Verifica existencias, calcula importe base, aplica descuento de mayoreo (10%
; en >= 5 unidades descartando fracciones de centavo), actualiza stock e ingresos.
; -----------------------------------------------------------------------------
RealizarVenta PROC
    pushad
    cmp numProductos, 0
    jne PedirCodVenta
    mov edx, OFFSET msgVacio
    call WriteString
    jmp FinVenta

PedirCodVenta:
    mov edx, OFFSET msgPedirCod
    call WriteString
    mov edx, OFFSET bufEntrada
    mov ecx, SIZEOF bufEntrada - 1
    call ReadString

    mov edx, OFFSET bufEntrada
    call ValidarFormatoCodigo
    cmp eax, 1
    je BuscarProdVenta
    mov edx, OFFSET errCodFormato
    call WriteString
    jmp PedirCodVenta

BuscarProdVenta:
    mov edx, OFFSET bufEntrada
    call BuscarProductoPorCodigo
    cmp eax, 1
    je VerificarHayStock
    mov edx, OFFSET errNoEncontrado
    call WriteString
    jmp FinVenta

VerificarHayStock:
    cmp DWORD PTR [esi + PRODUCTO.existencia], 0
    jne CapturarCantVenta
    mov edx, OFFSET errSinStock
    call WriteString
    jmp FinVenta

CapturarCantVenta:
    mov edx, OFFSET msgPedirCantV
    call WriteString
    mov edx, OFFSET bufEntrada
    mov ecx, SIZEOF bufEntrada - 1
    call ReadString

    mov edx, OFFSET bufEntrada
    call CadenaAEntero
    cmp ebx, 1
    jne ErrorCantV
    cmp eax, 0
    je ErrorCantV

    ; Comparar contra existencia disponible
    mov ebx, [esi + PRODUCTO.existencia]
    cmp eax, ebx
    ja ErrorStockInsuficiente

    mov auxCantidad, eax

    ; --- Calculo de Importe Base (precio * cantidad) ---
    mov eax, [esi + PRODUCTO.precio]
    mul auxCantidad             ; EAX = Importe base en centavos
    mov ebx, eax                ; EBX = Importe base
    xor ecx, ecx                ; ECX = Descuento (0 por defecto)

    ; --- Regla de Negocio: 10% de descuento si cantidad >= 5 ---
    cmp auxCantidad, 5
    jb CalcularTotalFinal
    mov eax, ebx
    xor edx, edx
    mov edi, 10
    div edi                     ; EAX = ImporteBase / 10 (descarta fraccion de centavo)
    mov ecx, eax                ; ECX = Descuento en centavos

CalcularTotalFinal:
    mov edi, ebx
    sub edi, ecx                ; EDI = Total final a pagar (Base - Descuento)

    ; --- Actualizar Inventario e Ingresos ---
    mov eax, auxCantidad
    sub [esi + PRODUCTO.existencia], eax
    add [esi + PRODUCTO.vendidos], eax
    add ingresosSesion, edi
    mov cambiosSinG, 1

    ; --- Imprimir Ticket de Venta ---
    mov edx, OFFSET lblTicket
    call WriteString

    mov edx, OFFSET lblSubtotal
    call WriteString
    mov eax, ebx
    call ImprimirMonedaMXN
    call Crlf

    mov edx, OFFSET lblDescuento
    call WriteString
    mov eax, ecx
    call ImprimirMonedaMXN
    call Crlf

    mov edx, OFFSET lblTotalVenta
    call WriteString
    mov eax, edi
    call ImprimirMonedaMXN
    call Crlf

    mov edx, OFFSET lblStockRest
    call WriteString
    mov eax, [esi + PRODUCTO.existencia]
    call ImprimirEntero
    call Crlf
    jmp FinVenta

ErrorCantV:
    mov edx, OFFSET errCantidad
    call WriteString
    jmp CapturarCantVenta

ErrorStockInsuficiente:
    mov edx, OFFSET errSinStock
    call WriteString
    jmp CapturarCantVenta

FinVenta:
    popad
    ret
RealizarVenta ENDP

; -----------------------------------------------------------------------------
; 4 y 6. MostrarResumen
; Recorre el catalogo con ESI para calcular total de unidades, valor total del
; inventario, ingresos de la sesion, producto mas vendido y alertas de stock.
; -----------------------------------------------------------------------------
MostrarResumen PROC
    pushad
    xor ebx, ebx                ; EBX = Total de unidades disponibles
    xor edi, edi                ; EDI = Valor total del inventario en centavos

    mov ecx, numProductos
    cmp ecx, 0
    je ImprimirDatosResumen

    mov esi, OFFSET catalogo
CicloResumenESI:
    mov eax, [esi + PRODUCTO.existencia]
    add ebx, eax                ; Sumar unidades

    mov edx, [esi + PRODUCTO.precio]
    mul edx                     ; EAX = existencia * precio
    add edi, eax                ; Sumar al valor del inventario

    add esi, TAM_PROD
    loop CicloResumenESI

ImprimirDatosResumen:
    mov edx, OFFSET lblResTitulo
    call WriteString

    mov edx, OFFSET lblResUnidades
    call WriteString
    mov eax, ebx
    call ImprimirEntero
    call Crlf

    mov edx, OFFSET lblResValor
    call WriteString
    mov eax, edi
    call ImprimirMonedaMXN
    call Crlf

    mov edx, OFFSET lblResIngresos
    call WriteString
    mov eax, ingresosSesion
    call ImprimirMonedaMXN
    call Crlf

    ; --- Demostracion de Regla de Negocio Adicional ---
    mov edx, OFFSET lblResRegla1
    call WriteString

    cmp numProductos, 0
    je FinResumen

    ; Buscar el producto mas vendido con ESI
    mov ecx, numProductos
    mov esi, OFFSET catalogo
    xor ebx, ebx                ; EBX = Mayor cantidad vendida encontrada
    xor edi, edi                ; EDI = Puntero al producto mas vendido

CicloMasVendidoESI:
    mov eax, [esi + PRODUCTO.vendidos]
    cmp eax, ebx
    jbe SiguienteMasVendido
    mov ebx, eax
    mov edi, esi
SiguienteMasVendido:
    add esi, TAM_PROD
    loop CicloMasVendidoESI

    cmp ebx, 0
    je MostrarSinVentas
    mov edx, OFFSET lblMasVendido
    call WriteString
    lea edx, [edi + PRODUCTO.nombre]
    call WriteString
    mov edx, OFFSET lblSep
    call WriteString
    mov eax, ebx
    call ImprimirEntero
    mov edx, OFFSET lblUnidades
    call WriteString
    jmp RevisarAlertasStock

MostrarSinVentas:
    mov edx, OFFSET lblSinVentas
    call WriteString

RevisarAlertasStock:
    mov ecx, numProductos
    mov esi, OFFSET catalogo
CicloAlertasESI:
    mov eax, [esi + PRODUCTO.existencia]
    cmp eax, 5
    jae SigAlerta
    mov edx, OFFSET lblAlertaStock
    call WriteString
    lea edx, [esi + PRODUCTO.nombre]
    call WriteString
    mov edx, OFFSET lblSep
    call WriteString
    call ImprimirEntero
    mov edx, OFFSET lblUnidades
    call WriteString
SigAlerta:
    add esi, TAM_PROD
    loop CicloAlertasESI

FinResumen:
    popad
    ret
MostrarResumen ENDP

; =============================================================================
; 4. PERSISTENCIA EN ARCHIVO Y VALIDACION INTEGRAL DE CARGA
; =============================================================================

; -----------------------------------------------------------------------------
; 5A. GuardarArchivo
; Guarda numProductos (4 bytes) + catalogo (480 bytes) = 484 bytes en disco.
; -----------------------------------------------------------------------------
GuardarArchivo PROC
    pushad
    mov edx, OFFSET nombreArchivo
    call CreateOutputFile
    cmp eax, INVALID_HANDLE_VALUE
    je ErrorGuardar

    mov manejadorArch, eax

    ; Escribir el bloque continuo de 484 bytes (numProductos + catalogo)
    mov eax, manejadorArch
    mov edx, OFFSET numProductos
    mov ecx, ARCHIVO_BYTES
    call WriteToFile
    cmp eax, ARCHIVO_BYTES
    jne CerrarYErrorG

    mov eax, manejadorArch
    call CloseFile

    mov cambiosSinG, 0
    mov edx, OFFSET okGuardado
    call WriteString
    jmp FinGuardar

CerrarYErrorG:
    mov eax, manejadorArch
    call CloseFile
ErrorGuardar:
    mov edx, OFFSET errArchivoG
    call WriteString
FinGuardar:
    popad
    ret
GuardarArchivo ENDP

; -----------------------------------------------------------------------------
; 5B. CargarArchivo
; Lee 'inventario.dat' en un buffer temporal, valida la integridad de todos
; los registros con ESI y solo reemplaza el catalogo activo si todo es valido.
; -----------------------------------------------------------------------------
CargarArchivo PROC
    pushad
    mov edx, OFFSET nombreArchivo
    call OpenInputFile
    cmp eax, INVALID_HANDLE_VALUE
    je ErrorCargar

    mov manejadorArch, eax

    ; Leer en buffer temporal (tempNumProd + tempCatalogo)
    mov eax, manejadorArch
    mov edx, OFFSET tempNumProd
    mov ecx, ARCHIVO_BYTES
    call ReadFromFile
    push eax                    ; Guardar bytes leidos
    mov eax, manejadorArch
    call CloseFile
    pop eax

    ; 1. Comprobar que el archivo tenga exactamente 484 bytes
    cmp eax, ARCHIVO_BYTES
    jne ErrorCargar

    ; 2. Validar que tempNumProd este entre 0 y 10
    mov ecx, tempNumProd
    cmp ecx, MAX_PROD
    ja ErrorCargar
    cmp ecx, 0
    je CopiarBufferACatalogo    ; Si es 0 productos validos, copiar directo

    ; 3. Recorrer tempCatalogo con ESI para validar cada campo antes de reemplazar
    mov esi, OFFSET tempCatalogo
CicloValidarArchivoESI:
    ; Validar formato de codigo ABC-123
    mov edx, esi
    call ValidarFormatoCodigo
    cmp eax, 1
    jne ErrorCargar

    ; Validar que el nombre no este vacio
    cmp BYTE PTR [esi + PRODUCTO.nombre], 0
    je ErrorCargar

    ; Validar rango de precio (1 a 999999 centavos)
    mov eax, [esi + PRODUCTO.precio]
    cmp eax, 1
    jb ErrorCargar
    cmp eax, 999999
    ja ErrorCargar

    ; Validar rango de existencia (0 a 100)
    mov eax, [esi + PRODUCTO.existencia]
    cmp eax, 100
    ja ErrorCargar

    add esi, TAM_PROD
    loop CicloValidarArchivoESI

    ; 4. Si todos los registros son validos, copiar al catalogo real
CopiarBufferACatalogo:
    mov ecx, ARCHIVO_BYTES
    mov esi, OFFSET tempNumProd
    mov edi, OFFSET numProductos
CicloReemplazo:
    mov al, [esi]
    mov [edi], al
    inc esi
    inc edi
    loop CicloReemplazo

    mov cambiosSinG, 0
    mov edx, OFFSET okCargado
    call WriteString
    jmp FinCargar

ErrorCargar:
    mov edx, OFFSET errArchivoC
    call WriteString
FinCargar:
    popad
    ret
CargarArchivo ENDP

END main