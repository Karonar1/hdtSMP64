#include "hdtCudaCollision.cuh"

#include "math.h"

namespace hdt
{
    constexpr int cuBlockSize() { return 1024; }

    template<typename T>
    constexpr int collisionBlockSize();

    // Per-triangle collisions currently use too many registers, so we need to reduce the block size
    template<>
    constexpr int collisionBlockSize<CudaPerVertexShape>() { return 1024; }
    template<>
    constexpr int collisionBlockSize<CudaPerTriangleShape>() { return 768; }

    __device__
        void subtract(const cuVector3& v1, const cuVector3& v2, cuVector3& result)
    {
        result.x = v1.x - v2.x;
        result.y = v1.y - v2.y;
        result.z = v1.z - v2.z;
        result.w = v1.w - v2.w;
    }

    __device__
        void add(const cuVector3& v1, const cuVector3& v2, cuVector3& result)
    {
        result.x = v1.x + v2.x;
        result.y = v1.y + v2.y;
        result.z = v1.z + v2.z;
        result.w = v1.w + v2.w;
    }

    __device__
        void multiply(const cuVector3& v, float c, cuVector3& result)
    {
        result.x = v.x * c;
        result.y = v.y * c;
        result.z = v.z * c;
        result.w = v.w * c;
    }

    __device__
        void crossProduct(const cuVector3& v1, const cuVector3& v2, cuVector3& result)
    {
        result.x = v1.y * v2.z - v1.z * v2.y;
        result.y = v1.z * v2.x - v1.x * v2.z;
        result.z = v1.x * v2.y - v1.y * v2.x;
    }

    __device__
        float dotProduct(const cuVector3& v1, const cuVector3& v2)
    {
        return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z;
    }

    __device__
        float magnitude(const cuVector3& v)
    {
        return sqrt(dotProduct(v, v));
    }

    __device__
        void normalize(cuVector3& v)
    {
        float mag = magnitude(v);
        v.x /= mag;
        v.y /= mag;
        v.z /= mag;
    }

    __device__
        bool boundingBoxCollision(const cuAabb& b1, const cuAabb& b2)
    {
        return !(b1.aabbMin.x > b2.aabbMax.x ||
            b1.aabbMin.y > b2.aabbMax.y ||
            b1.aabbMin.z > b2.aabbMax.z ||
            b1.aabbMax.x < b2.aabbMin.x ||
            b1.aabbMax.y < b2.aabbMin.y ||
            b1.aabbMax.z < b2.aabbMin.z);
    }

    __global__
        void kernelPerVertexUpdate(int n, const cuPerVertexInput* __restrict__ in, cuAabb* __restrict__ out, const cuVector3* __restrict__ vertexData)
    {
        int index = blockIdx.x * blockDim.x + threadIdx.x;
        int stride = blockDim.x * gridDim.x;

        for (int i = index; i < n; i += stride)
        {
            const cuVector3& v = vertexData[in[i].vertexIndex];
            float margin = v.w * in[i].margin;

            out[i].aabbMin.x = v.x - margin;
            out[i].aabbMin.y = v.y - margin;
            out[i].aabbMin.z = v.z - margin;
            out[i].aabbMax.x = v.x + margin;
            out[i].aabbMax.y = v.y + margin;
            out[i].aabbMax.z = v.z + margin;
        }
    }

    __global__
        void kernelPerTriangleUpdate(int n, const cuPerTriangleInput* __restrict__ in, cuAabb* __restrict__ out, const cuVector3* __restrict__ vertexData)
    {
        int index = blockIdx.x * blockDim.x + threadIdx.x;
        int stride = blockDim.x * gridDim.x;

        for (int i = index; i < n; i += stride)
        {
            const cuVector3& v0 = vertexData[in[i].vertexIndices[0]];
            const cuVector3& v1 = vertexData[in[i].vertexIndices[1]];
            const cuVector3& v2 = vertexData[in[i].vertexIndices[2]];

            float penetration = abs(in[i].penetration);
            float margin = max((v0.w + v1.w + v2.w) * in[i].margin / 3, penetration);

            out[i].aabbMin.x = min(v0.x, min(v1.x, v2.x)) - margin;
            out[i].aabbMin.y = min(v0.y, min(v1.y, v2.y)) - margin;
            out[i].aabbMin.z = min(v0.z, min(v1.z, v2.z)) - margin;
            out[i].aabbMax.x = max(v0.x, max(v1.x, v2.x)) + margin;
            out[i].aabbMax.y = max(v0.y, max(v1.y, v2.y)) + margin;
            out[i].aabbMax.z = max(v0.z, max(v1.z, v2.z)) + margin;
        }
    }

    __device__ cuVector3& operator+=(cuVector3& v1, cuVector3& v2)
    {
        v1.x += v2.x;
        v1.y += v2.y;
        v1.z += v2.z;
        v1.w += v2.w;
        return v1;
    }

    __device__ cuVector3 calcVertexState(const cuVector3& skinPos, const cuBone& bone, float w)
    {
        cuVector3 result;
        result.x = bone.transform[0].x * skinPos.x + bone.transform[1].x * skinPos.y + bone.transform[2].x * skinPos.z + bone.transform[3].x;
        result.y = bone.transform[0].y * skinPos.x + bone.transform[1].y * skinPos.y + bone.transform[2].y * skinPos.z + bone.transform[3].y;
        result.z = bone.transform[0].z * skinPos.x + bone.transform[1].z * skinPos.y + bone.transform[2].z * skinPos.z + bone.transform[3].z;
        result.w = bone.marginMultiplier.w;
        result.x *= w;
        result.y *= w;
        result.z *= w;
        result.w *= w;
        return result;
    }

    __global__
        void kernelBodyUpdate(int n, const cuVertex* __restrict__ in, cuVector3* __restrict__ out, const cuBone* __restrict__ boneData)
    {
        int index = blockIdx.x * blockDim.x + threadIdx.x;
        int stride = blockDim.x * gridDim.x;

        for (int i = index; i < n; i += stride)
        {
            out[i] = calcVertexState(in[i].position, boneData[in[i].bones[0]], in[i].weights[0]);
            for (int j = 1; j < 4; ++j)
            {
                out[i] += calcVertexState(in[i].position, boneData[in[i].bones[j]], in[i].weights[j]);
            }
        }
    }

    // collidePair does the actual collision between two colliders, always a vertex and some other type. It
    // should modify output if and only if there is a collision.
    __device__ bool collidePair(
        const cuPerVertexInput& __restrict__ inputA,
        const cuPerVertexInput& __restrict__ inputB,
        const cuVector3* __restrict__ vertexDataA,
        const cuVector3* __restrict__ vertexDataB,
        cuCollisionResult& output)
    {
        const cuVector3& vA = vertexDataA[inputA.vertexIndex];
        const cuVector3& vB = vertexDataB[inputB.vertexIndex];

        float rA = vA.w * inputA.margin;
        float rB = vB.w * inputB.margin;
        float bound2 = (rA + rB) * (rA + rB);
        cuVector3 diff;
        subtract(vA, vB, diff);
        float dist2 = dotProduct(diff, diff);
        float len = sqrt(dist2);
        float dist = len - (rA + rB);
        if (dist2 <= bound2 && (dist < output.depth))
        {
            if (len <= FLT_EPSILON)
            {
                diff = { 1, 0, 0, 0 };
            }
            else
            {
                normalize(diff);
            }
            output.depth = dist;
            output.normOnB = diff;
            multiply(diff, rA, output.posA);
            multiply(diff, rB, output.posB);
            subtract(vA, output.posA, output.posA);
            add(vB, output.posB, output.posB);
            return true;
        }
        return false;
    }

    __device__ bool collidePair(
        const cuPerVertexInput& __restrict__ inputA,
        const cuPerTriangleInput& __restrict__ inputB,
        const cuVector3* __restrict__ vertexDataA,
        const cuVector3* __restrict__ vertexDataB,
        cuCollisionResult& output)
    {
        cuVector3 s = vertexDataA[inputA.vertexIndex];
        float r = s.w * inputA.margin;
        cuVector3 p0 = vertexDataB[inputB.vertexIndices[0]];
        cuVector3 p1 = vertexDataB[inputB.vertexIndices[1]];
        cuVector3 p2 = vertexDataB[inputB.vertexIndices[2]];
        float margin = (p0.w + p1.w + p2.w) / 3.0;
        float penetration = inputB.penetration * margin;
        margin *= inputB.margin;
        if (penetration > -FLT_EPSILON && penetration < FLT_EPSILON)
        {
            penetration = 0;
        }

        // Compute unit normal and twice area of triangle
        cuVector3 ab;
        cuVector3 ac;
        subtract(p1, p0, ab);
        subtract(p2, p0, ac);
        cuVector3 normal;
        crossProduct(ab, ac, normal);
        float area = magnitude(normal);
        if (area < FLT_EPSILON)
        {
            return false;
        }
        multiply(normal, 1.0 / area, normal);

        // Reverse normal direction if penetration is negative
        if (penetration < 0)
        {
            multiply(normal, -1.0, normal);
            penetration = -penetration;
        }

        // Compute distance from point to plane and its projection onto the plane
        cuVector3 ap;
        subtract(s, p0, ap);
        float distance = dotProduct(ap, normal);
        cuVector3 projection;
        multiply(normal, distance, projection);
        subtract(s, projection, projection);

        // Determine whether the point is close enough to the plane
        float radiusWithMargin = r + margin;
        if (penetration >= FLT_EPSILON)
        {
            if (distance >= radiusWithMargin || distance < -penetration)
            {
                return false;
            }
        }
        else
        {
            if (distance < 0)
            {
                distance = -distance;
                multiply(normal, -1, normal);
            }
            if (distance >= radiusWithMargin)
            {
                return false;
            }
        }

        // Don't bother to do any more if depth isn't negative, or we already have a deeper collision
        float depth = distance - radiusWithMargin;
        if (depth >= -FLT_EPSILON || depth >= output.depth)
        {
            return false;
        }

        // Compute twice the area of each triangle formed by the projection
        cuVector3 bp;
        cuVector3 cp;
        subtract(projection, p0, ap);
        subtract(projection, p1, bp);
        subtract(projection, p2, cp);
        cuVector3 aa;
        crossProduct(bp, cp, aa);
        crossProduct(cp, ap, ab);
        crossProduct(ap, bp, ac);
        float areaA = magnitude(aa);
        float areaB = magnitude(ab);
        float areaC = magnitude(ac);
        if (areaA + areaB > area || areaB + areaC > area || areaC + areaA > area)
        {
            return false;
        }

        // FIXME: posA doesn't take the margin into account here
        output.normOnB = normal;
        output.posB = projection;
        multiply(normal, r, projection);
        subtract(s, projection, output.posA);
        output.depth = depth;
        return true;
    }

    // kernelCollision does the supporting work for threading the collision checks and making sure that only
    // the deepest result is kept.
    template <typename T>
    __global__ void kernelCollision(
        int n,
        const cuCollisionSetup<T>* __restrict__ setup,
        cuCollisionResult* output)
    {
        extern __shared__ float sdata[];

        for (int block = blockIdx.x; block < n; block += gridDim.x)
        {
            int nA = setup[block].sizeA;
            int nB = setup[block].sizeB;
            const cuPerVertexInput* inA = setup[block].colliderBufA;
            const auto* inB = setup[block].colliderBufB;
            const cuVector3* vertexDataA = setup[block].vertexDataA;
            const cuVector3* vertexDataB = setup[block].vertexDataB;
            const cuAabb* boundingBoxesA = setup[block].boundingBoxesA;
            const cuAabb* boundingBoxesB = setup[block].boundingBoxesB;

            // Depth should always be negative for collisions. We'll use positive values to signify no
            // collision, and later for mutual exclusion.
            int tid = threadIdx.x;
            cuCollisionResult temp;
            temp.depth = 1;

            int nPairs = nA * nB;
            for (int i = tid; i < nPairs; i += blockDim.x)
            {
                int iA = i % nA;
                int iB = i / nA;

                // Skip pairs with no bounding box collision. Doing this in a loop ought to reduce divergence
                // when pairs with such collisions are quite sparse.
                while (i < nPairs && !boundingBoxCollision(boundingBoxesA[iA], boundingBoxesB[iB]))
                {
                    i += blockDim.x;
                    iA = i % nA;
                    iB = i / nA;
                }

                if (i < nPairs && collidePair(inA[iA], inB[iB], vertexDataA, vertexDataB, temp))
                {
                    temp.colliderA = static_cast<cuCollider*>(0) + iA;
                    temp.colliderB = static_cast<cuCollider*>(0) + iB;
                }
            }

            // Set the best depth for this thread in shared memory
            sdata[tid] = temp.depth;

            // Now reduce to find the minimum depth, and store it in the first element
            __syncthreads();
            for (int s = blockDim.x / 2; s > 0; s >>= 1)
            {
                if (tid < s && sdata[tid] > sdata[tid + s])
                {
                    sdata[tid] = sdata[tid + s];
                }
                __syncthreads();
            }

            // If the depth of this thread is equal to the minimum, try to set the result. Do an atomic
            // exchange with the first value to ensure that only one thread gets to do this in case of ties.
            if (sdata[0] == temp.depth && atomicExch(sdata, 2) == temp.depth)
            {
                output[block] = temp;
            }
        }
    }

    void cuCreateStream(void** ptr)
    {
        *ptr = new cudaStream_t;
        cudaStreamCreate(reinterpret_cast<cudaStream_t*>(*ptr));
    }

    void cuDestroyStream(void* ptr)
    {
        cudaStreamDestroy(*reinterpret_cast<cudaStream_t*>(ptr));
        delete reinterpret_cast<cudaStream_t*>(ptr);
    }

    void cuGetDeviceBuffer(void** buf, int size)
    {
        cudaMalloc(buf, size);
    }

    void cuGetHostBuffer(void** buf, int size)
    {
        cudaMallocHost(buf, size);
    }

    void cuFreeDevice(void* buf)
    {
        cudaFree(buf);
    }

    void cuFreeHost(void* buf)
    {
        cudaFreeHost(buf);
    }

    void cuCopyToDevice(void* dst, void* src, size_t n, void* stream)
    {
        cudaStream_t* s = reinterpret_cast<cudaStream_t*>(stream);
        cudaMemcpyAsync(dst, src, n, cudaMemcpyHostToDevice, *s);
    }

    void cuCopyToHost(void* dst, void* src, size_t n, void* stream)
    {
        cudaStream_t* s = reinterpret_cast<cudaStream_t*>(stream);
        cudaMemcpyAsync(dst, src, n, cudaMemcpyDeviceToHost, *s);
    }

    bool cuRunBodyUpdate(void* stream, int n, cuVertex* input, cuVector3* output, cuBone* boneData)
    {
        cudaStream_t* s = reinterpret_cast<cudaStream_t*>(stream);
        int numBlocks = (n - 1) / cuBlockSize() + 1;

        kernelBodyUpdate <<<numBlocks, cuBlockSize(), 0, *s >>> (n, input, output, boneData);
        return cudaPeekAtLastError() == cudaSuccess;
    }

    bool cuRunPerVertexUpdate(void* stream, int n, cuPerVertexInput* input, cuAabb* output, cuVector3* vertexData)
    {
        cudaStream_t* s = reinterpret_cast<cudaStream_t*>(stream);
        int numBlocks = (n - 1) / cuBlockSize() + 1;

        kernelPerVertexUpdate <<<numBlocks, cuBlockSize(), 0, *s >>> (n, input, output, vertexData);
        return cudaPeekAtLastError() == cudaSuccess;
    }


    bool cuRunPerTriangleUpdate(void* stream, int n, cuPerTriangleInput* input, cuAabb* output, cuVector3* vertexData)
    {
        cudaStream_t* s = reinterpret_cast<cudaStream_t*>(stream);
        int numBlocks = (n - 1) / cuBlockSize() + 1;

        kernelPerTriangleUpdate <<<numBlocks, cuBlockSize(), 0, *s >>> (n, input, output, vertexData);
        return cudaPeekAtLastError() == cudaSuccess;
    }

    template<typename T>
    bool cuRunCollision(void* stream, int n, cuCollisionSetup<T>* setup, cuCollisionResult* output)
    {
        cudaStream_t* s = reinterpret_cast<cudaStream_t*>(stream);

        kernelCollision <<<n, collisionBlockSize<T>(), collisionBlockSize<T>() * sizeof(float), *s >>> (n, setup, output);
        return cudaPeekAtLastError() == cudaSuccess;
    }

    bool cuSynchronize(void* stream)
    {
        cudaStream_t* s = reinterpret_cast<cudaStream_t*>(stream);

        if (s)
        {
            return cudaStreamSynchronize(*s);
        }
        else
        {
            return cudaDeviceSynchronize() == cudaSuccess;
        }
    }

    void cuCreateEvent(void** ptr)
    {
        *ptr = new cudaEvent_t;
        cudaEventCreate(reinterpret_cast<cudaEvent_t*>(*ptr));
    }

    void cuDestroyEvent(void* ptr)
    {
        cudaEventDestroy(*reinterpret_cast<cudaEvent_t*>(ptr));
        delete reinterpret_cast<cudaEvent_t*>(ptr);
    }

    void cuRecordEvent(void* ptr, void* stream)
    {
        cudaEvent_t* e = reinterpret_cast<cudaEvent_t*>(ptr);
        cudaStream_t* s = reinterpret_cast<cudaStream_t*>(stream);
        cudaEventRecord(*e, *s);
    }

    void cuWaitEvent(void* ptr)
    {
        cudaEvent_t* e = reinterpret_cast<cudaEvent_t*>(ptr);
        cudaEventSynchronize(*e);
    }

    void cuInitialize()
    {
        cudaSetDeviceFlags(cudaDeviceScheduleYield);
    }

    template bool cuRunCollision<CudaPerVertexShape>(void*, int, cuCollisionSetup<CudaPerVertexShape>*, cuCollisionResult*);
    template bool cuRunCollision<CudaPerTriangleShape>(void*, int, cuCollisionSetup<CudaPerTriangleShape>*, cuCollisionResult*);
}
