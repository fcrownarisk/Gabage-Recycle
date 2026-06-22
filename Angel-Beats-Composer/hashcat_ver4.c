/**
 * btc_miner.c - 简化版比特币挖矿工具（类似HashCat的暴力枚举风格）
 * 编译: gcc -o btc_miner btc_miner.c -lcrypto -lpthread -O2 -Wall
 * 用法: ./btc_miner [-t 线程数] [-d 难度前导零位数] [-o 输出文件]
 * 
 * 功能: 模拟比特币挖矿，暴力枚举nonce寻找符合难度目标的区块哈希
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <time.h>
#include <openssl/sha.h>

/* ------------------------------- 常量 ----------------------------------- */
#define MAX_THREADS         64
#define DEFAULT_THREADS     4
#define DEFAULT_DIFFICULTY  4          /* 前导零位数（难度） */
#define MAX_NONCE           0xFFFFFFFF  /* 32位nonce最大值 */
#define HEADER_SIZE         80          /* 比特币区块头固定80字节 */

/* 区块头结构（小端字节序，简化版） */
typedef struct {
    uint32_t version;       /* 版本号 */
    uint8_t  prev_hash[32]; /* 前块哈希 */
    uint8_t  merkle_root[32];/* Merkle根 */
    uint32_t timestamp;     /* 时间戳 */
    uint32_t bits;          /* 难度目标 */
    uint32_t nonce;         /* 随机数 */
} block_header;

/* 全局配置 */
typedef struct {
    int difficulty;         /* 所需前导零个数（十六进制） */
    int threads;            /* 线程数 */
    char output_file[256];  /* 输出文件 */
    int verbose;            /* 详细输出 */
} Config;

Config g_config = {
    .difficulty = DEFAULT_DIFFICULTY,
    .threads = DEFAULT_THREADS,
    .output_file = "",
    .verbose = 1
};

/* 全局状态 */
volatile int g_found = 0;           /* 是否已找到有效nonce */
volatile uint32_t g_found_nonce = 0;
volatile unsigned long long g_total_hashes = 0;
pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;
clock_t g_start_time = 0;

/* ------------------------------- 工具函数 ------------------------------- */
/* 打印二进制哈希为十六进制字符串 */
void print_hash(const uint8_t *hash, int len) {
    for (int i = 0; i < len; i++)
        printf("%02x", hash[i]);
}

/* 检查哈希是否满足难度（前导零个数，以半字节即十六进制位计） */
int check_difficulty(const uint8_t *hash, int leading_nibbles) {
    int nibbles = 0;
    for (int i = 0; i < leading_nibbles; i++) {
        int byte = i / 2;
        int nibble = (i % 2) ? (hash[byte] & 0x0F) : (hash[byte] >> 4);
        if (nibble != 0) return 0;
        nibbles++;
    }
    return 1;
}

/* 双重SHA-256计算 */
void double_sha256(const uint8_t *data, size_t len, uint8_t *output) {
    uint8_t hash1[SHA256_DIGEST_LENGTH];
    SHA256(data, len, hash1);
    SHA256(hash1, SHA256_DIGEST_LENGTH, output);
}

/* 构造区块头（静态示例数据，实际应从外部获取） */
void build_block_header(block_header *header, uint32_t nonce) {
    /* 示例固定数据（实际挖矿需从网络获取真实值） */
    header->version = 0x20000000;
    memset(header->prev_hash, 0xAA, 32);      /* 模拟前块哈希 */
    memset(header->merkle_root, 0xBB, 32);    /* 模拟Merkle根 */
    header->timestamp = (uint32_t)time(NULL);
    header->bits = 0x1d00ffff;                /* 难度目标（简化） */
    header->nonce = nonce;
}

/* ------------------------------- 挖矿线程 ------------------------------- */
void* mine_thread(void *arg) {
    int thread_id = *(int*)arg;
    uint32_t start_nonce = thread_id;
    uint32_t step = g_config.threads;
    block_header header;
    uint8_t hash[SHA256_DIGEST_LENGTH];
    uint8_t header_bytes[HEADER_SIZE];
    unsigned long long local_hashes = 0;

    for (uint32_t nonce = start_nonce; nonce < MAX_NONCE && !g_found; nonce += step) {
        /* 构造区块头并序列化 */
        build_block_header(&header, nonce);
        memcpy(header_bytes, &header.version, 4);
        memcpy(header_bytes + 4, header.prev_hash, 32);
        memcpy(header_bytes + 36, header.merkle_root, 32);
        memcpy(header_bytes + 68, &header.timestamp, 4);
        memcpy(header_bytes + 72, &header.bits, 4);
        memcpy(header_bytes + 76, &header.nonce, 4);

        /* 计算哈希 */
        double_sha256(header_bytes, HEADER_SIZE, hash);
        local_hashes++;

        /* 检查难度 */
        if (check_difficulty(hash, g_config.difficulty)) {
            pthread_mutex_lock(&g_mutex);
            if (!g_found) {
                g_found = 1;
                g_found_nonce = nonce;
                printf("\n[+] 线程 %d 找到有效nonce: %u\n", thread_id, nonce);
                printf("   哈希: ");
                print_hash(hash, SHA256_DIGEST_LENGTH);
                printf("\n");
            }
            pthread_mutex_unlock(&g_mutex);
            break;
        }

        /* 定期更新全局哈希计数（每1000次更新一次） */
        if (local_hashes % 1000 == 0) {
            pthread_mutex_lock(&g_mutex);
            g_total_hashes += local_hashes;
            local_hashes = 0;
            pthread_mutex_unlock(&g_mutex);
        }
    }

    /* 最后累加剩余哈希 */
    pthread_mutex_lock(&g_mutex);
    g_total_hashes += local_hashes;
    pthread_mutex_unlock(&g_mutex);
    return NULL;
}

/* ------------------------------- 监控线程 ------------------------------- */
void* monitor_thread(void *arg) {
    while (!g_found) {
        sleep(1);
        pthread_mutex_lock(&g_mutex);
        unsigned long long hashes = g_total_hashes;
        pthread_mutex_unlock(&g_mutex);
        double elapsed = (double)(clock() - g_start_time) / CLOCKS_PER_SEC;
        double speed = hashes / elapsed;
        printf("\r[速度] %.2f MH/s | 已尝试: %llu | 时间: %.1f s",
               speed / 1e6, hashes, elapsed);
        fflush(stdout);
        if (g_found) break;
    }
    return NULL;
}

/* ------------------------------- 主函数 --------------------------------- */
int main(int argc, char *argv[]) {
    /* 简单命令行解析 */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-t") == 0 && i+1 < argc)
            g_config.threads = atoi(argv[++i]);
        else if (strcmp(argv[i], "-d") == 0 && i+1 < argc)
            g_config.difficulty = atoi(argv[++i]);
        else if (strcmp(argv[i], "-o") == 0 && i+1 < argc)
            strcpy(g_config.output_file, argv[++i]);
        else if (strcmp(argv[i], "-q") == 0)
            g_config.verbose = 0;
        else if (strcmp(argv[i], "-h") == 0) {
            printf("用法: %s [-t 线程数] [-d 难度前导零位数] [-o 输出文件] [-q]\n", argv[0]);
            printf("示例: %s -t 4 -d 5\n", argv[0]);
            return 0;
        }
    }

    if (g_config.threads > MAX_THREADS) g_config.threads = MAX_THREADS;
    if (g_config.difficulty > 32) g_config.difficulty = 32;

    printf("========================================\n");
    printf("  HashCat风格比特币挖矿工具\n");
    printf("  线程数: %d | 难度(前导零十六进制位): %d\n", g_config.threads, g_config.difficulty);
    printf("========================================\n");

    g_start_time = clock();

    /* 创建挖矿线程 */
    pthread_t threads[MAX_THREADS];
    int thread_ids[MAX_THREADS];
    for (int i = 0; i < g_config.threads; i++) {
        thread_ids[i] = i;
        pthread_create(&threads[i], NULL, mine_thread, &thread_ids[i]);
    }

    /* 创建监控线程 */
    pthread_t monitor_tid;
    pthread_create(&monitor_tid, NULL, monitor_thread, NULL);

    /* 等待所有挖矿线程结束 */
    for (int i = 0; i < g_config.threads; i++)
        pthread_join(threads[i], NULL);

    /* 通知监控线程退出 */
    pthread_cancel(monitor_tid);
    pthread_join(monitor_tid, NULL);

    double elapsed = (double)(clock() - g_start_time) / CLOCKS_PER_SEC;
    printf("\n\n========== 挖矿结果 ==========\n");
    if (g_found) {
        printf("✅ 成功找到有效nonce: %u\n", g_found_nonce);
        printf("总尝试哈希数: %llu\n", g_total_hashes);
        printf("平均算力: %.2f MH/s\n", (g_total_hashes / 1e6) / elapsed);
        if (strlen(g_config.output_file) > 0) {
            FILE *fp = fopen(g_config.output_file, "w");
            if (fp) {
                fprintf(fp, "nonce=%u\n", g_found_nonce);
                fprintf(fp, "total_hashes=%llu\n", g_total_hashes);
                fclose(fp);
                printf("结果已保存至 %s\n", g_config.output_file);
            }
        }
    } else {
        printf("❌ 在 %u 范围内未找到有效nonce\n", MAX_NONCE);
    }
    printf("耗时: %.2f 秒\n", elapsed);
    return 0;
}