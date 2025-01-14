/*
 * keccak.cu  Implementation of Keccak/SHA3 digest
 *
 * Date: 12 June 2019
 * Revision: 1
 *
 * This file is released into the Public Domain.
 */
 
// Edited & optimized by krlnokrl
 
 
typedef unsigned char BYTE;
typedef uint32_t  WORD;
typedef uint64_t LONG; 
 

#define KECCAK_ROUND 24
#define KECCAK_STATE_SIZE 25
#define KECCAK_Q_SIZE 65

#define DIGESTBITLEN 256
#define RATE_BITS 1088 	//1600 - (256 << 1)
#define RATE_BYTES 136 	// RATE_BITS >> 3
#define ABSORB_ROUND 17	//RATE_BITS >> 6

__constant__ LONG CUDA_KECCAK_CONSTS[24] = { 0x0000000000000001, 0x0000000000008082,
                                          0x800000000000808a, 0x8000000080008000, 0x000000000000808b, 0x0000000080000001, 0x8000000080008081,
                                          0x8000000000008009, 0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
                                          0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003, 0x8000000000008002,
                                          0x8000000000000080, 0x000000000000800a, 0x800000008000000a, 0x8000000080008081, 0x8000000000008080,
                                          0x0000000080000001, 0x8000000080008008 };

typedef struct {

    int64_t state[KECCAK_STATE_SIZE];
    BYTE q[KECCAK_Q_SIZE];

    WORD bits_in_queue;

} cuda_keccak_ctx_t;
typedef cuda_keccak_ctx_t CUDA_KECCAK_CTX;


__device__ __forceinline__ static uint64_t xor5(const uint64_t a, const uint64_t b, const uint64_t c, const uint64_t d, const uint64_t e)
{
	uint64_t result;
	asm("xor.b64 %0, %1, %2;" : "=l"(result) : "l"(d) ,"l"(e));
	asm("xor.b64 %0, %0, %1;" : "+l"(result) : "l"(c));
	asm("xor.b64 %0, %0, %1;" : "+l"(result) : "l"(b));
	asm("xor.b64 %0, %0, %1;" : "+l"(result) : "l"(a));
	return result;
}


__device__ __forceinline__ uint64_t cuda_keccak_ROTL64(const uint64_t x, const int offset) {
	uint64_t res;
	asm("{ // ROTL64 \n\t"
		".reg .u32 tl,th,vl,vh;\n\t"
		".reg .pred p;\n\t"
		"mov.b64 {tl,th}, %1;\n\t"
		"shf.l.wrap.b32 vl, tl, th, %2;\n\t"
		"shf.l.wrap.b32 vh, th, tl, %2;\n\t"
		"setp.lt.u32 p, %2, 32;\n\t"
		"@!p mov.b64 %0, {vl,vh};\n\t"
		"@p  mov.b64 %0, {vh,vl};\n\t"
	"}\n" : "=l"(res) : "l"(x) , "r"(offset)
	);
	return res;
}
/*__device__ __forceinline__ LONG cuda_keccak_ROTL64(LONG a, const int  b)
{
    return (a << b) | (a >> (64 - b));
}
*/



__device__ __forceinline__ static void cuda_keccak_permutations(cuda_keccak_ctx_t * ctx)
{

    int64_t* A = ctx->state;

    int64_t *a00 = A, *a01 = A + 1, *a02 = A + 2, *a03 = A + 3, *a04 = A + 4;
    int64_t *a05 = A + 5, *a06 = A + 6, *a07 = A + 7, *a08 = A + 8, *a09 = A + 9;
    int64_t *a10 = A + 10, *a11 = A + 11, *a12 = A + 12, *a13 = A + 13, *a14 = A + 14;
    int64_t *a15 = A + 15, *a16 = A + 16, *a17 = A + 17, *a18 = A + 18, *a19 = A + 19;
    int64_t *a20 = A + 20, *a21 = A + 21, *a22 = A + 22, *a23 = A + 23, *a24 = A + 24;
	
	int64_t c0;
	int64_t c1;
	int64_t c2;
	int64_t c3;
	int64_t c4;
	
	int64_t d0;
	int64_t d1;
	int64_t d2;
	int64_t d3;
	int64_t d4;
	
	#pragma unroll 2
    for (int i = 0; i < KECCAK_ROUND; i++) {

        /* Theta */
        /*
		c0 = *a00 ^ *a05 ^ *a10 ^ *a15 ^ *a20;
        c1 = *a01 ^ *a06 ^ *a11 ^ *a16 ^ *a21;
        c2 = *a02 ^ *a07 ^ *a12 ^ *a17 ^ *a22;
        c3 = *a03 ^ *a08 ^ *a13 ^ *a18 ^ *a23;
        c4 = *a04 ^ *a09 ^ *a14 ^ *a19 ^ *a24;
		*/
		c0 = xor5(*a00, *a05, *a10, *a15, *a20);
		c1 = xor5(*a01, *a06, *a11, *a16, *a21);
		c2 = xor5(*a02, *a07, *a12, *a17, *a22);
		c3 = xor5(*a03, *a08, *a13, *a18, *a23);
		c4 = xor5(*a04, *a09, *a14, *a19, *a24);
		
        d1 = cuda_keccak_ROTL64(c1, 1) ^ c4;
        d2 = cuda_keccak_ROTL64(c2, 1) ^ c0;
        d3 = cuda_keccak_ROTL64(c3, 1) ^ c1;
        d4 = cuda_keccak_ROTL64(c4, 1) ^ c2;
        d0 = cuda_keccak_ROTL64(c0, 1) ^ c3;

        *a00 ^= d1;
        *a05 ^= d1;
        *a10 ^= d1;
        *a15 ^= d1;
        *a20 ^= d1;
        *a01 ^= d2;
        *a06 ^= d2;
        *a11 ^= d2;
        *a16 ^= d2;
        *a21 ^= d2;
        *a02 ^= d3;
        *a07 ^= d3;
        *a12 ^= d3;
        *a17 ^= d3;
        *a22 ^= d3;
        *a03 ^= d4;
        *a08 ^= d4;
        *a13 ^= d4;
        *a18 ^= d4;
        *a23 ^= d4;
        *a04 ^= d0;
        *a09 ^= d0;
        *a14 ^= d0;
        *a19 ^= d0;
        *a24 ^= d0;

        /* Rho pi */
        c1 = cuda_keccak_ROTL64(*a01, 1);
        *a01 = cuda_keccak_ROTL64(*a06, 44);
        *a06 = cuda_keccak_ROTL64(*a09, 20);
        *a09 = cuda_keccak_ROTL64(*a22, 61);
        *a22 = cuda_keccak_ROTL64(*a14, 39);
        *a14 = cuda_keccak_ROTL64(*a20, 18);
        *a20 = cuda_keccak_ROTL64(*a02, 62);
        *a02 = cuda_keccak_ROTL64(*a12, 43);
        *a12 = cuda_keccak_ROTL64(*a13, 25);
        *a13 = cuda_keccak_ROTL64(*a19, 8);
        *a19 = cuda_keccak_ROTL64(*a23, 56);
        *a23 = cuda_keccak_ROTL64(*a15, 41);
        *a15 = cuda_keccak_ROTL64(*a04, 27);
        *a04 = cuda_keccak_ROTL64(*a24, 14);
        *a24 = cuda_keccak_ROTL64(*a21, 2);
        *a21 = cuda_keccak_ROTL64(*a08, 55);
        *a08 = cuda_keccak_ROTL64(*a16, 45);
        *a16 = cuda_keccak_ROTL64(*a05, 36);
        *a05 = cuda_keccak_ROTL64(*a03, 28);
        *a03 = cuda_keccak_ROTL64(*a18, 21);
        *a18 = cuda_keccak_ROTL64(*a17, 15);
        *a17 = cuda_keccak_ROTL64(*a11, 10);
        *a11 = cuda_keccak_ROTL64(*a07, 6);
        *a07 = cuda_keccak_ROTL64(*a10, 3);
        *a10 = c1;

        /* Chi */
        c0 = *a00 ^ (~*a01 & *a02);
        c1 = *a01 ^ (~*a02 & *a03);
        *a02 ^= ~*a03 & *a04;
        *a03 ^= ~*a04 & *a00;
        *a04 ^= ~*a00 & *a01;
        *a00 = c0;
        *a01 = c1;

        c0 = *a05 ^ (~*a06 & *a07);
        c1 = *a06 ^ (~*a07 & *a08);
        *a07 ^= ~*a08 & *a09;
        *a08 ^= ~*a09 & *a05;
        *a09 ^= ~*a05 & *a06;
        *a05 = c0;
        *a06 = c1;

        c0 = *a10 ^ (~*a11 & *a12);
        c1 = *a11 ^ (~*a12 & *a13);
        *a12 ^= ~*a13 & *a14;
        *a13 ^= ~*a14 & *a10;
        *a14 ^= ~*a10 & *a11;
        *a10 = c0;
        *a11 = c1;

        c0 = *a15 ^ (~*a16 & *a17);
        c1 = *a16 ^ (~*a17 & *a18);
        *a17 ^= ~*a18 & *a19;
        *a18 ^= ~*a19 & *a15;
        *a19 ^= ~*a15 & *a16;
        *a15 = c0;
        *a16 = c1;

        c0 = *a20 ^ (~*a21 & *a22);
        c1 = *a21 ^ (~*a22 & *a23);
        *a22 ^= ~*a23 & *a24;
        *a23 ^= ~*a24 & *a20;
        *a24 ^= ~*a20 & *a21;
        *a20 = c0;
        *a21 = c1;

        /* Iota */
        *a00 ^= CUDA_KECCAK_CONSTS[i];
    }
}



__device__ __forceinline__ void cuda_keccak_pad(cuda_keccak_ctx_t *ctx)
{
    ctx->q[ctx->bits_in_queue >> 3] |= (1L << (ctx->bits_in_queue & 7));

    ++(ctx->bits_in_queue);


    LONG full = ctx->bits_in_queue >> 6;
    LONG partial = ctx->bits_in_queue & 63;

    LONG offset = 0;
	
	#pragma unroll 4
    for (int i = 0; i < full; ++i) {
        ctx->state[i] ^= *((uint64_t*)(ctx->q + offset));
        offset += 8;
    }

    if (partial > 0) {
        LONG mask = (1L << partial) - 1;
        ctx->state[full] ^= *((uint64_t*)(ctx->q + offset)) & mask;
    }

    ctx->state[(RATE_BITS - 1) >> 6] ^= 9223372036854775808ULL;/* 1 << 63 */

    cuda_keccak_permutations(ctx);

    ctx->bits_in_queue = RATE_BITS;
}


__device__ __forceinline__ void cuda_keccak_init(cuda_keccak_ctx_t *ctx)
{
    memset(ctx, 0, sizeof(cuda_keccak_ctx_t));

    ctx->bits_in_queue = 0;
}

__device__ __forceinline__ void cuda_keccak_update(cuda_keccak_ctx_t *ctx, BYTE* const in, const WORD inlen){
	int64_t BYTEs = ctx->bits_in_queue >> 3;
	memcpy(ctx->q + BYTEs, in, inlen);
	BYTEs += inlen;
	ctx->bits_in_queue = BYTEs << 3;
}


__device__ __forceinline__ void cuda_keccak_final(cuda_keccak_ctx_t *ctx, BYTE *out)
{
    cuda_keccak_pad(ctx);
    WORD i = 0;
    memcpy(out, ctx->state , 8);

}