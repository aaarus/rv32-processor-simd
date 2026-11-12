/* RV32I compiler target plus the two individually verified R-type operations.
   All tested vectors (<= 2048 elements) fit safely in signed int32. */
typedef signed char i8;
typedef unsigned int u32;

static inline int mul_low(int a, int b) {
    int r;
    __asm__ volatile (".insn r 0x33, 0, 1, %0, %1, %2"
                      : "=r"(r) : "r"(a), "r"(b));
    return r;
}

static inline int dot4(u32 a, u32 b) {
    int r;
    __asm__ volatile (".insn r 0x0b, 0, 0, %0, %1, %2"
                      : "=r"(r) : "r"(a), "r"(b));
    return r;
}
/* Aligned hardware load, without a C pointer cast that violates strict aliasing. */
static inline u32 load_aligned(const i8 *p) {
    u32 r;
    __asm__ volatile ("lw %0, 0(%1)" : "=r"(r) : "r"(p) : "memory");
    return r;
}

static inline u32 pack_bytes(const i8 *p) {
    return (u32)(unsigned char)p[0] | ((u32)(unsigned char)p[1] << 8)
         | ((u32)(unsigned char)p[2] << 16) | ((u32)(unsigned char)p[3] << 24);
}

__attribute__((noinline))
int scalar_dot(const i8 *a, const i8 *b, unsigned n) {
    int sum = 0;
    for (unsigned i = 0; i < n; ++i)
        sum += mul_low(a[i], b[i]);
    return sum;
}

__attribute__((noinline))
int simd_dot(const i8 *a, const i8 *b, unsigned n) {
    int sum = 0;
    /* Different alignments cannot be repaired by advancing both pointers. */
    if (((u32)a ^ (u32)b) & 3) {
        while (n >= 4) {
            sum += dot4(pack_bytes(a), pack_bytes(b));
            a += 4;
            b += 4;
            n -= 4;
        }
    } else {
        while (n && ((u32)a & 3)) {
            sum += mul_low(*a++, *b++);
            --n;
        }
        while (n >= 4) {
            sum += dot4(load_aligned(a), load_aligned(b));
            a += 4;
            b += 4;
            n -= 4;
        }
    }
    while (n--)
        sum += mul_low(*a++, *b++);
    return sum;
}

int main(void) {
    volatile u32 *control = (volatile u32 *)16;
    unsigned n = control[0], variant = control[1];
    const i8 *a = (const i8 *)control[2];
    const i8 *b = (const i8 *)control[3];
    for (int repeat = 0; repeat < 2; ++repeat) {
        __asm__ volatile ("addi x31, x0, 1" ::: "memory");
        int result = variant ? simd_dot(a, b, n) : scalar_dot(a, b, n);
        __asm__ volatile ("sw %0, 0(zero)" : : "r"(result) : "memory");
        __asm__ volatile ("addi x31, x0, 2" : : "r"(result) : "memory");
    }
    return 0;
}
