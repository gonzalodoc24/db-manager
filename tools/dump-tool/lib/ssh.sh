#!/bin/bash

# =============================================================================
# Manejo del túnel SSH
# Encapsula apertura, verificación y cierre del túnel.
# Usa ControlMaster para gestionar el proceso SSH de forma confiable.
# =============================================================================

_SSH_CONTROL_PATH="/tmp/dump-tool-${SSH_USER}@${SSH_HOST}:${LOCAL_PORT}"

start_ssh_tunnel() {
    local key_path="${HOME}/${SSH_PRIVATE_KEY_PATH}"

    [[ -f "$key_path" ]] || die "Clave SSH no encontrada: $key_path"

    if verify_ssh_tunnel; then
        log_warn "Ya existe un túnel SSH activo. Se reutiliza."
        return 0
    fi

    log_info "Abriendo túnel SSH: ${SSH_USER}@${SSH_HOST} → localhost:${LOCAL_PORT} → ${DB_HOST}:${DB_PORT}"

    ssh \
        -i "$key_path" \
        -L "${LOCAL_PORT}:${DB_HOST}:${DB_PORT}" \
        -o ControlMaster=yes \
        -o ControlPath="${_SSH_CONTROL_PATH}" \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        -N -f \
        "${SSH_USER}@${SSH_HOST}" 2>&1

    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        die "No se pudo abrir el túnel SSH (código: $exit_code). Verificar credenciales y host."
    fi

    sleep 2

    verify_ssh_tunnel || die "El túnel SSH no quedó operativo tras el inicio."
    log_success "Túnel SSH activo."
}

verify_ssh_tunnel() {
    ssh \
        -o ControlPath="${_SSH_CONTROL_PATH}" \
        -O check \
        "${SSH_USER}@${SSH_HOST}" > /dev/null 2>&1
}

stop_ssh_tunnel() {
    if verify_ssh_tunnel; then
        log_info "Cerrando túnel SSH..."
        ssh \
            -o ControlPath="${_SSH_CONTROL_PATH}" \
            -O exit \
            "${SSH_USER}@${SSH_HOST}" > /dev/null 2>&1
        log_success "Túnel SSH cerrado."
    else
        log_warn "No se encontró un túnel SSH activo."
    fi
}
