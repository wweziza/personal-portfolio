; server.asm
; Compile with: nasm -f elf32 server.asm
; Link with: ld -m elf_i386 server.o pages/index.o pages/about.o -o server

extern index_content
extern index_content_end
extern about_content
extern about_content_end

section .data
    listen_sock dd 0
    client_sock dd 0
    
    ; HTTP response headers
    http_ok db 'HTTP/1.1 200 OK', 13, 10
    content_type db 'Content-Type: text/html', 13, 10
    content_length_header db 'Content-Length: ', 0
    newline db 13, 10, 13, 10

    ; Error messages
    error_socket db 'Failed to create socket', 10, 0
    error_bind db 'Failed to bind to port', 10, 0
    error_listen db 'Failed to listen on socket', 10, 0
    error_accept db 'Failed to accept client connection', 10, 0

    ; Debug messages
    debug_request db 'Received request: ', 0
    debug_route_index db 'Matched index route', 10, 0
    debug_route_about db 'Matched about route', 10, 0
    debug_route_unknown db 'Unknown route', 10, 0

    ; Request buffer
    request_buffer times 1024 db 0

    ; Routes
    route_index db 'GET / ', 0
    route_about db 'GET /about ', 0

section .bss
    sockaddr_in resb 16
    content_length_str resb 20

section .text
    global _start

_start:
    ; Create socket
    mov eax, 102         ; socketcall
    mov ebx, 1           ; SYS_SOCKET
    push 0               ; Protocol
    push 1               ; SOCK_STREAM
    push 2               ; AF_INET
    mov ecx, esp
    int 0x80
    add esp, 12
    test eax, eax
    js exit_error
    mov [listen_sock], eax

    ; Bind to port 80
    mov word [sockaddr_in], 2          ; AF_INET
    mov word [sockaddr_in + 2], 0x5000  ; Port 80 (network byte order)
    mov dword [sockaddr_in + 4], 0      ; INADDR_ANY

    mov eax, 102         ; socketcall
    mov ebx, 2           ; SYS_BIND
    push 16              ; sockaddr_in size
    push sockaddr_in     ; sockaddr_in struct
    push dword [listen_sock]  ; socket fd
    mov ecx, esp
    int 0x80
    add esp, 12
    test eax, eax
    js exit_error

    ; Listen for connections
    mov eax, 102         ; socketcall
    mov ebx, 4           ; SYS_LISTEN
    push 5               ; backlog
    push dword [listen_sock]  ; socket fd
    mov ecx, esp
    int 0x80
    add esp, 8
    test eax, eax
    js exit_error

accept_loop:
    ; Accept client connection
    mov eax, 102         ; socketcall
    mov ebx, 5           ; SYS_ACCEPT
    push 0               ; addrlen
    push 0               ; addr
    push dword [listen_sock]  ; socket fd
    mov ecx, esp
    int 0x80
    add esp, 12
    test eax, eax
    js exit_error
    mov [client_sock], eax

    ; Read request
    mov eax, 3           ; read
    mov ebx, [client_sock]
    mov ecx, request_buffer
    mov edx, 1024
    int 0x80

    ; Debug: Print received request
    push eax
    push ecx
    mov eax, 4
    mov ebx, 1
    mov ecx, debug_request
    mov edx, 19
    int 0x80
    mov eax, 4
    mov ebx, 1
    mov ecx, request_buffer
    pop edx
    int 0x80
    pop ecx

    ; Parse request and send response
    mov esi, request_buffer
    mov edi, route_about
    call string_compare
    test eax, eax
    jz .send_about

    mov esi, request_buffer
    mov edi, route_index
    call string_compare
    test eax, eax
    jz .send_index

    ; Unknown route
    mov eax, 4
    mov ebx, 1
    mov ecx, debug_route_unknown
    mov edx, 14
    int 0x80
    jmp .send_index  ; Default to index for unknown routes

.send_index:
    mov eax, 4
    mov ebx, 1
    mov ecx, debug_route_index
    mov edx, 19
    int 0x80
    mov esi, index_content
    mov edi, index_content_end
    jmp .send_response

.send_about:
    mov eax, 4
    mov ebx, 1
    mov ecx, debug_route_about
    mov edx, 19
    int 0x80
    mov esi, about_content
    mov edi, about_content_end

.send_response:
    ; Calculate content length
    mov eax, edi
    sub eax, esi
    push eax
    call int_to_string

    ; Send HTTP headers
    mov eax, 4
    mov ebx, [client_sock]
    mov ecx, http_ok
    mov edx, 17
    int 0x80

    mov eax, 4
    mov ebx, [client_sock]
    mov ecx, content_type
    mov edx, 25
    int 0x80

    mov eax, 4
    mov ebx, [client_sock]
    mov ecx, content_length_header
    mov edx, 16
    int 0x80

    mov eax, 4
    mov ebx, [client_sock]
    mov ecx, content_length_str
    mov edx, eax
    int 0x80

    mov eax, 4
    mov ebx, [client_sock]
    mov ecx, newline
    mov edx, 4
    int 0x80

    ; Send content
    mov eax, 4
    mov ebx, [client_sock]
    mov ecx, esi
    pop edx
    int 0x80

    ; Close client socket
    mov eax, 6
    mov ebx, [client_sock]
    int 0x80

    jmp accept_loop

exit_error:
    ; Print error message
    mov eax, 4
    mov ebx, 2
    mov ecx, error_socket
    mov edx, 26
    int 0x80

    ; Exit
    mov eax, 1
    mov ebx, 1
    int 0x80
; Compare two null-terminated strings
; esi: first string (request), edi: second string (route)
; Returns 0 if route matches, non-zero if different
; Compare only the first few characters of the request
string_compare:
    push esi
    push edi
    .loop:
        mov al, [esi]
        mov bl, [edi]
        cmp bl, 0  ; Stop if we've reached the end of the route string
        je .equal
        cmp al, bl
        jne .not_equal
        inc esi
        inc edi
        jmp .loop
    .not_equal:
        mov eax, 1
        jmp .done
    .equal:
        xor eax, eax
    .done:
        pop edi
        pop esi
        ret



; Convert integer to string
; eax: integer to convert
; Returns: eax = length of string, content_length_str = resulting string
int_to_string:
    push ebx
    push ecx
    push edx
    push esi
    mov ebx, 10
    mov esi, content_length_str
    add esi, 19  ; Start from the end of the buffer
    mov byte [esi], 0  ; Null-terminate

    ; Handle the special case of 0
    test eax, eax
    jnz .loop
    dec esi
    mov byte [esi], '0'
    jmp .done

.loop:
    xor edx, edx
    div ebx
    add dl, '0'
    dec esi
    mov [esi], dl
    test eax, eax
    jnz .loop

.done:
    ; Calculate length
    mov eax, content_length_str
    add eax, 19
    sub eax, esi  ; eax now contains the length of the string

    ; Move the string to the beginning of the buffer
    mov ecx, eax  ; ecx = length
    inc ecx       ; include null terminator
    mov edi, content_length_str
    rep movsb

    pop esi
    pop edx
    pop ecx
    pop ebx
    ret