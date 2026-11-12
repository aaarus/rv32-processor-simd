/* Inserted after the original matmul definition, before forward().
   Calls the original implementation first; captures read-only copies afterward. */
static void capture_ints(FILE *f, const int8_t *p, int n) {
    fputc('[',f);
    for(int i=0;i<n;i++) fprintf(f,"%s%d",i?",":"",(int)p[i]);
    fputc(']',f);
}
static void capture_scales(FILE *f, const float *p, int n) {
    fputc('[',f);
    for(int i=0;i<n;i++) fprintf(f,"%s%.9g",i?",":"",(double)p[i]);
    fputc(']',f);
}
void matmul(float *out, QuantizedTensor *x, QuantizedTensor *w, int n, int d) {
    static int call=0;
    matmul_original(out,x,w,n,d);
    int current=call++;
    /* First-layer query/down projections at token positions zero and one.
       This selection is for the pinned 6-layer model: 7*6+1 calls/token. */
    if (current!=0 && current!=6 && current!=43 && current!=49) return;
    const char *path=getenv("LLM_CAPTURE");
    if(!path) return;
    FILE *f=fopen(path,"a");
    if(!f) { perror("capture"); exit(1); }
    for(int row=0;row<2 && row<d;row++) {
        fprintf(f,"{\"call\":%d,\"row\":%d,\"n\":%d,\"d\":%d,\"group_size\":%d,\"a\":",
                current,row,n,d,GS);
        capture_ints(f,w->q+row*n,n);
        fprintf(f,",\"b\":"); capture_ints(f,x->q,n);
        fprintf(f,",\"weight_scales\":"); capture_scales(f,w->s+row*n/GS,n/GS);
        fprintf(f,",\"activation_scales\":"); capture_scales(f,x->s,n/GS);
        fprintf(f,",\"scaled_output\":%.9g}\n",(double)out[row]);
    }
    fclose(f);
}
