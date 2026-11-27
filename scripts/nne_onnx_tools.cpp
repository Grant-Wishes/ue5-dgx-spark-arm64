// libNNEEditorOnnxTools.so for Linux arm64 (DGX Spark, 26 Nov 2026).
//
// Epic ships this helper of the NNE editor only as prebuilt binaries (x86_64 on Linux), so the arm64 editor logged
// "Failed to load the NNEEditorOnnxTools shared library". Its job is small and its C interface is declared in
// NNEEditorOnnxTools.h: parse an ONNX ModelProto and list the external data files its tensors point to (tensors whose
// weights live outside the .onnx, "location" entries of TensorProto.external_data). This is an independent
// implementation of that interface: a minimal protobuf wire-format reader, no protobuf or onnx dependency.
//
// It visits every TensorProto an ONNX model can hold: graph initializers, sparse initializers (values and indices), node
// attributes (t, tensors, sparse_tensor(s)), sub-graphs in attributes (g, graphs, recursively), training graphs and
// function bodies. Locations are returned once each, in the order they first appear.
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace
{
enum class Status : uint8_t { Ok = 0, FailCannotParseAsModelProto };

struct Reader
{
	const uint8_t* P;
	const uint8_t* End;
	bool Ok = true;

	bool AtEnd() const { return P >= End || !Ok; }

	uint64_t Varint()
	{
		uint64_t V = 0;
		for (int Shift = 0; Shift < 64; Shift += 7)
		{
			if (P >= End) { Ok = false; return 0; }
			const uint8_t B = *P++;
			V |= uint64_t(B & 0x7f) << Shift;
			if (!(B & 0x80)) { return V; }
		}
		Ok = false;
		return 0;
	}

	// Reads one field header; returns false at the end or on malformed input.
	bool Next(uint32_t& Field, uint32_t& WireType)
	{
		if (AtEnd()) { return false; }
		const uint64_t Key = Varint();
		Field = uint32_t(Key >> 3);
		WireType = uint32_t(Key & 7);
		return Ok && Field != 0;
	}

	// Length-delimited payload as a sub-reader.
	Reader Bytes()
	{
		const uint64_t Len = Varint();
		if (!Ok || Len > uint64_t(End - P)) { Ok = false; return Reader{P, P}; }
		Reader R{P, P + Len};
		P += Len;
		return R;
	}

	void Skip(uint32_t WireType)
	{
		switch (WireType)
		{
		case 0: Varint(); break;
		case 1: if (End - P < 8) { Ok = false; } else { P += 8; } break;
		case 2: Bytes(); break;
		case 5: if (End - P < 4) { Ok = false; } else { P += 4; } break;
		default: Ok = false; break;   // groups (3, 4) are not used by onnx.proto
		}
	}
};

struct Collector
{
	std::vector<std::string> Paths;
	bool Ok = true;

	void Add(std::string Location)
	{
		for (const std::string& P : Paths) { if (P == Location) { return; } }
		Paths.push_back(std::move(Location));
	}

	// StringStringEntryProto: key = 1, value = 2
	void Entry(Reader R)
	{
		std::string Key, Value;
		uint32_t F, W;
		while (R.Next(F, W))
		{
			if ((F == 1 || F == 2) && W == 2)
			{
				Reader S = R.Bytes();
				(F == 1 ? Key : Value).assign(reinterpret_cast<const char*>(S.P), S.End - S.P);
			}
			else { R.Skip(W); }
		}
		Ok &= R.Ok;
		if (Key == "location" && !Value.empty()) { Add(Value); }
	}

	// TensorProto: external_data = 13
	void Tensor(Reader R)
	{
		uint32_t F, W;
		while (R.Next(F, W))
		{
			if (F == 13 && W == 2) { Entry(R.Bytes()); }
			else { R.Skip(W); }
		}
		Ok &= R.Ok;
	}

	// SparseTensorProto: values = 1, indices = 2 (both TensorProto)
	void SparseTensor(Reader R)
	{
		uint32_t F, W;
		while (R.Next(F, W))
		{
			if ((F == 1 || F == 2) && W == 2) { Tensor(R.Bytes()); }
			else { R.Skip(W); }
		}
		Ok &= R.Ok;
	}

	// AttributeProto: t = 5, g = 6, tensors = 10, graphs = 11, sparse_tensor = 22, sparse_tensors = 23
	void Attribute(Reader R, int Depth)
	{
		uint32_t F, W;
		while (R.Next(F, W))
		{
			if (W != 2) { R.Skip(W); continue; }
			switch (F)
			{
			case 5: case 10: Tensor(R.Bytes()); break;
			case 6: case 11: Graph(R.Bytes(), Depth + 1); break;
			case 22: case 23: SparseTensor(R.Bytes()); break;
			default: R.Skip(W); break;
			}
		}
		Ok &= R.Ok;
	}

	// NodeProto: attribute = 5
	void Node(Reader R, int Depth)
	{
		uint32_t F, W;
		while (R.Next(F, W))
		{
			if (F == 5 && W == 2) { Attribute(R.Bytes(), Depth); }
			else { R.Skip(W); }
		}
		Ok &= R.Ok;
	}

	// GraphProto: node = 1, initializer = 5, sparse_initializer = 15
	void Graph(Reader R, int Depth)
	{
		if (Depth > 64) { Ok = false; return; }   // malformed or hostile nesting
		uint32_t F, W;
		while (R.Next(F, W))
		{
			if (W != 2) { R.Skip(W); continue; }
			switch (F)
			{
			case 1: Node(R.Bytes(), Depth); break;
			case 5: Tensor(R.Bytes()); break;
			case 15: SparseTensor(R.Bytes()); break;
			default: R.Skip(W); break;
			}
		}
		Ok &= R.Ok;
	}

	// TrainingInfoProto: initialization = 1, algorithm = 2 (GraphProto)
	void TrainingInfo(Reader R)
	{
		uint32_t F, W;
		while (R.Next(F, W))
		{
			if ((F == 1 || F == 2) && W == 2) { Graph(R.Bytes(), 0); }
			else { R.Skip(W); }
		}
		Ok &= R.Ok;
	}

	// FunctionProto: node = 7
	void Function(Reader R)
	{
		uint32_t F, W;
		while (R.Next(F, W))
		{
			if (F == 7 && W == 2) { Node(R.Bytes(), 0); }
			else { R.Skip(W); }
		}
		Ok &= R.Ok;
	}

	// ModelProto: graph = 7, training_info = 20, functions = 25. A ModelProto must have a graph.
	bool Model(Reader R)
	{
		bool bGraph = false;
		uint32_t F, W;
		while (R.Next(F, W))
		{
			if (W != 2) { R.Skip(W); continue; }
			switch (F)
			{
			case 7: Graph(R.Bytes(), 0); bGraph = true; break;
			case 20: TrainingInfo(R.Bytes()); break;
			case 25: Function(R.Bytes()); break;
			default: R.Skip(W); break;
			}
		}
		return Ok && R.Ok && R.P == R.End && bGraph;
	}
};
}

struct NNEEditorOnnxTools_ExternalDataDescriptor
{
	std::vector<std::string> Paths;
	size_t Next = 0;
};

extern "C"
{
__attribute__((visibility("default"))) Status NNEEditorOnnxTools_CreateExternalDataDescriptor(const void* InData, const int Size,
	NNEEditorOnnxTools_ExternalDataDescriptor** Descriptor)
{
	if (!Descriptor) { return Status::FailCannotParseAsModelProto; }
	*Descriptor = nullptr;
	if (!InData || Size <= 0) { return Status::FailCannotParseAsModelProto; }
	const uint8_t* Data = static_cast<const uint8_t*>(InData);
	Collector C;
	if (!C.Model(Reader{Data, Data + Size})) { return Status::FailCannotParseAsModelProto; }
	*Descriptor = new NNEEditorOnnxTools_ExternalDataDescriptor{std::move(C.Paths), 0};
	return Status::Ok;
}

__attribute__((visibility("default"))) void NNEEditorOnnxTools_ReleaseExternalDataDescriptor(NNEEditorOnnxTools_ExternalDataDescriptor** Descriptor)
{
	if (Descriptor && *Descriptor)
	{
		delete *Descriptor;
		*Descriptor = nullptr;
	}
}

__attribute__((visibility("default"))) const char* NNEEditorOnnxTools_GetNextExternalDataPath(NNEEditorOnnxTools_ExternalDataDescriptor* Descriptor)
{
	if (!Descriptor || Descriptor->Next >= Descriptor->Paths.size()) { return nullptr; }
	return Descriptor->Paths[Descriptor->Next++].c_str();
}
}
