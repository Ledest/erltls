#ifndef ERLTLS_C_SRC_NIF_SSL_SOCKET_H_
#define ERLTLS_C_SRC_NIF_SSL_SOCKET_H_

#include "erl_nif.h"

ERL_NIF_TERM enif_ssl_socket_new(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM enif_ssl_socket_handshake(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM enif_ssl_socket_send_pending(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM enif_ssl_socket_feed_data(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM enif_ssl_socket_send_data(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM enif_ssl_socket_shutdown(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]);
void enif_ssl_socket_free(ErlNifEnv* env, void* obj);

#endif