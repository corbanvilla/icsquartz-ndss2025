#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define ROUND_UP(num, divisor) (((num) + (divisor)-1) / (divisor))

/* These structs need to have idential sizes and layouts with */
/* the corresponding ST ones. See `artifacts/build/main.ll`   */
/* for references to each of these. */
struct BASE64_ENCODE_STREAM {
    int8_t (*t1)[48]; // [48]
    int8_t (*t2)[64]; // [64]
    int16_t t3;
    int16_t t4;
    int16_t t5;
    int16_t t6;
    int16_t t7;
    int16_t t8;
    int16_t t9;
    int16_t t10;
    int8_t t11[65];
};

struct BASE64_ENCODE_STR {
    int8_t t1;
    int8_t t2;
    int8_t (*t3)[145];
    int8_t (*t4)[193];
    struct BASE64_ENCODE_STREAM BASE64_ENCODE_STREAM;
    int8_t t5;
    int8_t t6[48];
    int8_t t9[64];
    int16_t t10;
    int16_t t11;
    int16_t t12;
    int16_t t13;
    int16_t t14;
    int8_t t15[81];
};

struct BASE64_DEMO_struct {
    int8_t text1[145];
    int8_t text2[193];
    struct BASE64_ENCODE_STR BASE64_ENCODE_STR;
    int8_t start;
    int8_t done1;
};

extern "C"
{
    void BASE64_DEMO(struct BASE64_DEMO_struct *);
    extern struct BASE64_DEMO_struct BASE64_DEMO_instance;
}

extern "C"
{
    void PLC_PRG(struct PLC_PRG_struct *);
    extern struct PLC_PRG_struct PLC_PRG_instance;
    size_t PLC_PRG_instance_size = sizeof(struct BASE64_DEMO_fuzzer_instance);
    size_t PLC_PRG_input_size = PLC_PRG_instance_size;
    size_t PLC_PRG_struct_size = PLC_PRG_instance_size;
}

/* This instance stores all default values from ST. Do not overwrite values! */
// extern struct BASE64_DEMO_struct BASE64_DEMO_instance;
/* This instance is for running. Clone the struct above before each run! */
struct BASE64_DEMO_struct BASE64_DEMO_fuzzer_instance;

extern "C" int LLVMFuzzerTestOneInput(uint8_t *Data, size_t Size)
{
    /* Fresh copy of default values every run */
    memcpy(&BASE64_DEMO_fuzzer_instance, &BASE64_DEMO_instance, sizeof(struct BASE64_DEMO_struct));

    // Disallow empty inputs
    if (Size == 0)
        return 0;

    // Allow calling with inputs of size N, which will be looped through
    // to look for state bugs
    int iterations = ROUND_UP(Size, 144);

    for (int i = 0; i < iterations; i++) {
        /* Calculate where to copy into the data array */
        uint8_t* data_ptr = Data + (i * 144);
        uint8_t data_size = 144; 
        if (i+1 == iterations) {
            data_size = Size % (144+1);
        }

        /* Copy in fuzzer values to local struct */
        memcpy(BASE64_DEMO_fuzzer_instance.text1, data_ptr, data_size);
        /* Null-terminate fuzzer input */
        BASE64_DEMO_fuzzer_instance.text1[data_size] = '\0';

        /* Call multiple times to fish for state bugs */
        for (int i = 0; i < 3; i++) {
            /* Invoke the ST program */
            BASE64_DEMO(&BASE64_DEMO_fuzzer_instance);
        }

        /* Reset just enough state to allow it to run again */
        /* Maximizes the chances of finding bugs in state reset */
        BASE64_DEMO_fuzzer_instance.start = 1;
        BASE64_DEMO_fuzzer_instance.BASE64_ENCODE_STR.t5 = 0;
    }
    // #endif

    #ifdef RUN_ONE_CYCLE
    if (Size <= 144) {
        /* Copy in fuzzer values to local struct */
        memcpy(BASE64_DEMO_fuzzer_instance.text1, Data, MIN(144,Size));
        /* Null-terminate fuzzer input */
        BASE64_DEMO_fuzzer_instance.text1[Size] = '\0';

        /* Call multiple times to fish for state bugs */
        for (int i = 0; i < 3; i++) {
            /* Invoke the ST program */
            BASE64_DEMO(&BASE64_DEMO_fuzzer_instance);
        }
    }
    #endif

    #ifdef RUN_ONCE
    if (Size <= 144) {
        // Fuzz once (reset state every time)
        /* Copy in default values to local struct */
        memcpy(BASE64_DEMO_fuzzer_instance.text1, Data, MIN(Size,144));
        /* Null-terminate fuzzer input */
        BASE64_DEMO_fuzzer_instance.text1[Size] = '\0';
        /* Invoke the ST program */
        BASE64_DEMO(&BASE64_DEMO_fuzzer_instance);
    }
    #endif
    
    return 0;
}
