#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <semaphore.h>

#include <cuda_runtime.h>

#include "simpleMultiGPU.h"

//const int DATA_N = 10000000;
const int DATA_N = 100;


void* gpu_monitor(void* arg);
__global__ void add(int* a, int n);

sem_t localGPU_TaskSizeSubmit_sem;     
sem_t localGPU_TaskSubmit_sem;         
sem_t localGPU_beginComputation_sem;   
sem_t localGPU_computationFin_sem;

typedef struct
{
    //Host-side input data and computation result,if computation is not int summary,typedef sth substitute int
    int taskNo;
	int result;
	void *ptBegin;   	//reserved   raw data poniter(if taskNo > 4     malloc)
	int *ptSize;		//reserved   raw data size poniter(if taskNo > 4     malloc)
    void *begin[4];  	//initial container for raw data pointer
	int size[4];		//initial container for raw data size pointer; in bytes
}	GPUTask;

GPUTask gpuTask;

int main()
{
	int res;
    pthread_t gpu_thread;
    void *thread_result;

	res = sem_init(&localGPU_TaskSizeSubmit_sem, 0, 0);
	if(res != 0)
	{
		perror("sem localGPU_TaskSubmit_sem initialization failed");
		exit(EXIT_FAILURE);
	}

	res = sem_init(&localGPU_TaskSubmit_sem, 0, 0);
	if(res != 0)
	{
		perror("sem localGPU_TaskSubmit_sem initialization failed");
		exit(EXIT_FAILURE);
	}
	res = sem_init(&localGPU_beginComputation_sem, 0, 0);
	if(res != 0)
	{
	perror("sem localGPU_beginComputation_sem initialization failed");
	exit(EXIT_FAILURE);
	}
	res = sem_init(&localGPU_computationFin_sem, 0, 0);
	if(res != 0)
	{
		perror("sem localGPU_computationFin_sem initialization failed");
		exit(EXIT_FAILURE);
	}
	res = pthread_create(&gpu_thread, NULL, gpu_monitor, NULL);
	if (res != 0)
	{
		perror("Thread creation failed");
		exit(EXIT_FAILURE);
	}

	//gpuTask.taskNo = 4;
	gpuTask.taskNo = 2;
	int i, j;
	
	for(i = 0; i < gpuTask.taskNo; i++)
	{
		gpuTask.size[i] = DATA_N * sizeof(int);
	}

	sem_post(&localGPU_TaskSizeSubmit_sem);

	sem_wait(&localGPU_TaskSubmit_sem);

	int * intArray;
	int cpuSum = 0;
	for(i = 0;i < gpuTask.taskNo; i++)
	{
		intArray = (int *)gpuTask.begin[i];
		for(j = 0; j < DATA_N; j++)
			cpuSum += intArray[j] = j;
	}
	sem_post(&localGPU_beginComputation_sem);
	sem_wait(&localGPU_computationFin_sem);
	printf("The sum of gpu is %d\n", gpuTask.result);
	printf("The sum of cpu is %d\n", cpuSum);

    res = pthread_join(gpu_thread, &thread_result);
    if (res != 0) {
        perror("Thread join failed");
        exit(EXIT_FAILURE);
    }
    printf("Thread joined\n");
 
	sem_destroy(&localGPU_TaskSizeSubmit_sem);
	sem_destroy(&localGPU_TaskSubmit_sem);
	sem_destroy(&localGPU_beginComputation_sem);
	sem_destroy(&localGPU_computationFin_sem);
    exit(EXIT_SUCCESS);	

	return 0;
}

void *gpu_monitor(void *arg) {
	sem_wait(&localGPU_TaskSizeSubmit_sem);  // P²Ù×÷
	
	//int GPU_num = 0;
	//cudaGetDeviceCount(&GPU_num);
	//printf("The count of GPU is %d\n", GPU_num);	
	
	TGPUplan plan[4];
	int i, j;
	
	for(i = 0; i < gpuTask.taskNo; i++)
	{
		gpuTask.begin[i] = malloc(gpuTask.size[i]);
		cudaSetDevice(i);
		cudaStreamCreate(&plan[i].stream);
		cudaMalloc((void**)&plan[i].d_Data, gpuTask.size[i]);
		//cudaMallocHost((void**)&plan[i].h_Sum, sizeof(int));
		cudaMallocHost((void**)&plan[i].h_Data, gpuTask.size[i]);

		plan[i].h_Sum = (int *)malloc(sizeof(int));

		printf("GPU %d cudaMalloc success.\n", i);

	}
	
	sem_post(&localGPU_TaskSubmit_sem);   // V²Ù×÷
	
	sem_wait(&localGPU_beginComputation_sem);	
	
	int sumGPUs = 0;
	int *intArray;

	for(i = 0; i < gpuTask.taskNo; i++)
	{
		intArray = (int* )gpuTask.begin[i];
		for(j = 0; j < DATA_N; j++)
			plan[i].h_Data[j] = intArray[j];
	}

	for(i = 0; i < gpuTask.taskNo; i++)
	{
		cudaSetDevice(i);
		cudaMemcpyAsync(plan[i].d_Data, plan[i].h_Data, gpuTask.size[i], cudaMemcpyHostToDevice, plan[i].stream);
		printf("cudaMemcpy success.\n");

		add_kernel<<<1, 2, 0, plan[i].stream>>>(plan[i].d_Data, DATA_N);

		cudaMemcpyAsync(plan[i].h_Sum, plan[i].d_Data, sizeof(int), cudaMemcpyDeviceToHost, plan[i].stream);
		sumGPUs += plan[i].h_Sum[0];
		printf("sum: %d\n", plan[i].h_Sum[0]);

		cudaFree(plan[i].d_Data);
		cudaFreeHost(plan[i].h_Data);
		cudaStreamDestroy(plan[i].stream);
	}

	gpuTask.result = sumGPUs;
	sem_post(&localGPU_computationFin_sem);

	return 0;
}
