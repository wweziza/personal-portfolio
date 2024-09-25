; Linux x86 Assembly HTTP Server

extern index_content
extern about_content

section .data
    ; Constants
    STDIN equ 0
    STDOUT equ 1
    STDERR equ 2
    AF_INET equ 2
    SOCK_STREAM equ 1
    INADDR_ANY equ 0
    SOL_SOCKET equ 1
    SO_REUSEADDR equ 2

    ; System call numbers
    SYS_READ equ 3
    SYS_WRITE equ 4
    SYS_SOCKET equ 359
    SYS_BIND equ 361
    SYS_LISTEN equ 363
    SYS_ACCEPT equ 364
    SYS_CLOSE equ 6
    SYS_EXIT equ 1

    ; Messages
    msg_server_start db "Server started on port 80", 10, 0
    msg_server_start_len equ $ - msg_server_start
    msg_conn_accepted db "New connection accepted", 10, 0
    msg_conn_accepted_len equ $ - msg_conn_accepted
    msg_conn_closed db "Connection closed", 10, 0
    msg_conn_closed_len equ $ - msg_conn_closed
    msg_request_received db "Request received: ", 0
    msg_request_received_len equ $ - msg_request_received

    ; HTTP headers
    http_header db "HTTP/1.1 200 OK", 13, 10
                db "Content-Type: text/html", 13, 10
                db "Connection: close", 13, 10, 13, 10
    http_header_len equ $ - http_header

    ; Socket address structure
    sockaddr_in:
        sin_family dw AF_INET
        sin_port dw 0x5000 ; Port 80 in network byte order
        sin_addr dd INADDR_ANY
        sin_zero times 8 db 0

    ; Paths
    path_root db "/", 0
    path_about db "/about", 0

    ; Not found message
    not_found_msg db "HTTP/1.1 404 Not Found", 13, 10
                  db "Content-Type: text/html", 13, 10
                  db "Connection: close", 13, 10, 13, 10
                  db "<html><body><h1>404 Not Found</h1></body></html>", 0
    not_found_len equ $ - not_found_msg

section .bss
    sockfd resd 1
    clientfd resd 1
    buffer resb 1024

section .text
    global _start

_start:
    ; Create socket
    mov eax, SYS_SOCKET
    mov ebx, AF_INET
    mov ecx, SOCK_STREAM
    xor edx, edx
    int 0x80
    mov [sockfd], eax

    ; Set SO_REUSEADDR
    push dword 1
    mov ecx, esp
    push dword 4
    push ecx
    push dword SO_REUSEADDR
    push dword SOL_SOCKET
    push dword [sockfd]
    mov eax, 366 ; setsockopt
    mov ebx, [sockfd]
    mov ecx, SOL_SOCKET
    mov edx, SO_REUSEADDR
    int 0x80
    add esp, 20

    ; Bind socket
    mov eax, SYS_BIND
    mov ebx, [sockfd]
    mov ecx, sockaddr_in
    mov edx, 16
    int 0x80

    ; Listen for connections
    mov eax, SYS_LISTEN
    mov ebx, [sockfd]
    mov ecx, 5
    int 0x80

    ; Print server start message
    mov eax, SYS_WRITE
    mov ebx, STDOUT
    mov ecx, msg_server_start
    mov edx, msg_server_start_len
    int 0x80

accept_loop:
    ; Accept connection
    mov eax, SYS_ACCEPT
    mov ebx, [sockfd]
    xor ecx, ecx
    xor edx, edx
    int 0x80
    mov [clientfd], eax

    ; Print connection accepted message
    mov eax, SYS_WRITE
    mov ebx, STDOUT
    mov ecx, msg_conn_accepted
    mov edx, msg_conn_accepted_len
    int 0x80

    ; Handle client request
    call handle_request

    ; Close client connection
    mov eax, SYS_CLOSE
    mov ebx, [clientfd]
    int 0x80

    ; Print connection closed message
    mov eax, SYS_WRITE
    mov ebx, STDOUT
    mov ecx, msg_conn_closed
    mov edx, msg_conn_closed_len
    int 0x80

    jmp accept_loop

handle_request:
    ; Read client request
    mov eax, SYS_READ
    mov ebx, [clientfd]
    mov ecx, buffer
    mov edx, 1024
    int 0x80

    ; Check if any data was read
    test eax, eax
    jle .done ; Skip processing if no data was read or error occurred

    ; ... [request printing and parsing remain unchanged] ...

    ; Compare path with "/about"
    mov esi, buffer
    mov edi, path_about
    call strcmp
    test eax, eax
    jz serve_about

    ; Compare path with "/"
    mov esi, buffer
    mov edi, path_root
    call strcmp
    test eax, eax
    jz serve_index

    ; If no match, send 404 response
    mov eax, SYS_WRITE
    mov ebx, [clientfd]
    mov ecx, not_found_msg
    mov edx, not_found_len
    int 0x80

.done:
    ret

serve_index:
    ; Send HTTP header
    mov eax, SYS_WRITE
    mov ebx, [clientfd]
    mov ecx, http_header
    mov edx, http_header_len
    int 0x80

    ; Send index content
    mov eax, SYS_WRITE
    mov ebx, [clientfd]
    mov ecx, index_content
    mov edx, 2048 ; Adjust this based on actual content size
    int 0x80
    ret

serve_about:
    ; Send HTTP header
    mov eax, SYS_WRITE
    mov ebx, [clientfd]
    mov ecx, http_header
    mov edx, http_header_len
    int 0x80

    ; Send about content
    mov eax, SYS_WRITE
    mov ebx, [clientfd]
    mov ecx, about_content
    mov edx, 2048 ; Adjust this based on actual content size
    int 0x80
    ret

strcmp:
    ; Compare strings in ESI and EDI
    .loop:
        lodsb           ; Load byte from [ESI]
        scasb           ; Compare it with byte at [EDI]
        jne .not_equal  ; If not equal, exit with non-zero
        test al, al     ; Check if end of string (null terminator)
        jnz .loop       ; If not end, continue loop
        xor eax, eax    ; If equal, set eax to 0
        ret
    .not_equal:
        mov eax, 1      ; Set eax to non-zero to indicate not equal
        ret

parse_request:
    ; Simple path parsing (assumes request starts with "GET ")
    mov esi, buffer
    add esi, 4 ; Skip "GET "

    ; Copy path to the beginning of the buffer
    mov edi, buffer
    .loop:
        lodsb
        cmp al, ' '
        je .done
        stosb
        jmp .loop
    .done:
    xor al, al  ; Null-terminate the string
    stosb
    ret

close_connection:
    ret

exit:
    mov eax, SYS_EXIT
    xor ebx, ebx
    int 0x80