//
//  patcher.m
//  GestaltHax
//
//  Created by Hana on 15/03/24.
//


#include <stdio.h>
#include <stdlib.h>
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <dlfcn.h>
#include <string.h>


off_t find_offset(const char* mgKey) {
    // --- DEBUG START: find_offset ---
    printf("\n--- DEBUG START: Finding offset for key: '%s' ---\n", mgKey);
    
    const struct mach_header_64 *header = NULL;
    const char *mgName = "/usr/lib/libMobileGestalt.dylib";
    
    // Step 1: Load and Locate libMobileGestalt.dylib
    printf("DEBUG 1/5: Loading target library: %s\n", mgName);
    dlopen(mgName, RTLD_GLOBAL);

    for (int i = 0; i < _dyld_image_count(); i++) {
        if (!strncmp(mgName, _dyld_get_image_name(i), strlen(mgName))) {
            header = (const struct mach_header_64 *)_dyld_get_image_header(i);
            printf("DEBUG 1/5: Target library header found.\n");
            break;
        }
    }

    if (!header) {
        fprintf(stderr, "ERROR: Failed to find libMobileGestalt.dylib header.\n");
        return -1;
    }
    
    uintptr_t runtime_base_address = (uintptr_t)header;
    
    // --- REBASE INFORMATION ---
    printf("NEW Image Base Address (Runtime Load Address): **0x%llx**\n", (unsigned long long)runtime_base_address);
    printf(">>> END Rebase Information <<<\n\n");
    // --------------------------


    // Step 2: Locate the encrypted key string in __TEXT.__cstring
    size_t textCStringSize;
    const char *textCStringSection = (const char *)getsectiondata(header, "__TEXT", "__cstring", &textCStringSize);
    printf("DEBUG 2/5: Searching for string in __TEXT.__cstring (Size: %zu bytes).\n", textCStringSize);
    
    const char *string_address = NULL;
    
    for (size_t size = 0; size < textCStringSize; size += strlen(textCStringSection + size) + 1) {
        if (!strncmp(mgKey, textCStringSection + size, strlen(mgKey))) {
            string_address = textCStringSection + size;
            textCStringSection += size;
            break;
        }
    }

    if (!string_address) {
        printf("DEBUG 2/5: Key string '%s' not found in __TEXT.__cstring.\n", mgKey);
        return -1;
    }

    printf("DEBUG 2/5: Key string found: '%s'\n", string_address);

    // Step 3: Locate the pointer (Xref) to the key string
    size_t constSize;
    const char *const_section_name = "__AUTH_CONST";
    const uintptr_t *constSection = (const uintptr_t *)getsectiondata(header, "__AUTH_CONST", "__const", &constSize);
    
    if (!constSection) {
        const_section_name = "__DATA_CONST";
        constSection = (const uintptr_t *)getsectiondata(header, "__DATA_CONST", "__const", &constSize);
    }
    
    if (!constSection) {
        fprintf(stderr, "ERROR: Failed to find __const section.\n");
        return -1;
    }
    
    printf("DEBUG 3/5: Searching for pointer to string (0x%llx) in %s.__const (Size: %zu).\n", (unsigned long long)string_address, const_section_name, constSize);

    uintptr_t pointer_address = 0;
    
    for (int i = 0; i < constSize / sizeof(uintptr_t); i++) {
        if (constSection[i] == (uintptr_t)textCStringSection) {
            pointer_address = (uintptr_t)&constSection[i];
            constSection += i;
            break;
        }
    }
    
    if (pointer_address == 0) {
        printf("DEBUG 3/5: Pointer (Xref) to key string not found.\n");
        return -1;
    }

    printf("DEBUG 3/5: Pointer to key string found at virtual address: **0x%llx**\n", (unsigned long long)pointer_address);
    
    // Step 4: Determine the address of the raw offset value
    uintptr_t raw_offset_address = (uintptr_t)constSection + 0x9a;
    

    
    uint16_t raw_value = ((uint16_t *)constSection)[0x9a / 2];
    
    printf("DEBUG: Raw uint16_t value read: **0x%x** (Decimal: %u)\n", raw_value, raw_value);


    // Step 5: Final calculation
    off_t offset = (off_t)raw_value;

    printf("DEBUG 5/5: Final calculation: (Raw Value) * 8 = 0x%x * 8\n", raw_value);
    printf("DEBUG 5/5: The final Gestalt key offset is: **0x%llx**\n", (unsigned long long)offset);
    
    printf("--- DEBUG END: find_offset ---\n");
    return offset;
}

typedef struct {
    const char *label;
    const char *obfuscated_string;
} PatchEntry;

/**
 * @brief Searches for the Nth occurrence of the 0xFFFFFFFF00000000 pattern.
 * * @param buffer The data buffer to search within.
 * @param size The size of the buffer.
 * @param n The occurrence number to find (e.g., 2 for the second).
 * @return off_t The offset of the pattern, or -1 if not found.
 */
off_t find_pattern_offset(const unsigned char *buffer, size_t size, int n) {
    // Pattern: 0xFFFFFFFF00000000 (8 bytes)
    // Little-endian byte sequence:
    // FFFFFFFF (first 4 bytes) -> 0xFF, 0xFF, 0xFF, 0xFF
    // 00000000 (last 4 bytes)  -> 0x00, 0x00, 0x00, 0x00
    const unsigned char pattern[] = {0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00};
    const size_t pattern_len = sizeof(pattern);
    int found_count = 0;

    if (size < pattern_len) {
        return -1;
    }

    for (size_t offset = 0; offset <= size - pattern_len; ++offset) {
        if (memcmp(buffer + offset, pattern, pattern_len) == 0) {
            found_count++;
            if (found_count == n) {
                return (off_t)offset;
            }
        }
    }
    return -1; // Nth occurrence not found
}


void patch_buffer(unsigned char *buffer, size_t size) {
    if (!buffer || size == 0) {
        fprintf(stderr, "Invalid buffer or size.\n");
        return;
    }

    PatchEntry patches[] = {
        {"EffectiveSecurityModeAp", "vENa/R1xAXLobl8r3PBL6w"},
    };

    size_t num_patches = sizeof(patches) / sizeof(patches[0]);

    // --- Search for the second pattern first ---
    // User requested the offset of the second "FFFFFFFF 00000000" sequence (N=2)
    off_t pattern_offset = find_pattern_offset(buffer, size, 2);

    if (pattern_offset == -1) {
        printf("DEBUG: Required pattern (2nd occurrence of 0xFFFFFFFF00000000) not found. Skipping patch.\n");
        return;
    }
    
    printf("\nDEBUG: Pattern 0xFFFFFFFF00000000 found at offset: 0x%llx\n", pattern_offset);
    

    // Apply the patch logic for each key
    for (size_t i = 0; i < num_patches; ++i) {
        // 1. Get the Gestalt Key Offset
        off_t gestalt_key_offset = find_offset(patches[i].obfuscated_string);
        
        printf("DEBUG: Key: %s | Gestalt Offset found: 0x%llx\n", patches[i].label, gestalt_key_offset);

        if (gestalt_key_offset != -1) {
            
            // 2. Calculate the final patch offset
            // Final Offset = Pattern Offset + 8 + Gestalt Key Offset
            off_t final_patch_offset = pattern_offset + 7 + gestalt_key_offset;

            printf("DEBUG: Final Patch Calculation: Pattern Offset (0x%llx) + 8 + Gestalt Offset (0x%llx) = 0x%llx\n",
                   pattern_offset, gestalt_key_offset, final_patch_offset);

            // 3. Apply Patch
            if (final_patch_offset < size) {
                // The patching operation: set the byte to 0x00
                buffer[final_patch_offset] = 0x01;
                
                printf("Found %s offset at: 0x%llx. Patched byte at **0x%llx** to **0x01**.\n",
                       patches[i].label, gestalt_key_offset, final_patch_offset);
            } else {
                fprintf(stderr, "Error: Final calculated offset (0x%llx) is outside buffer size (%zu).\n",
                        final_patch_offset, size);
            }
        } else {
            printf("Could not find Gestalt key offset for: %s\n", patches[i].label);
        }
    }

    printf("Patching done.\n");
}




@interface PlistModifier : NSObject
- (void)modifyPlistAtPath:(NSString *)path;
@end

@implementation PlistModifier

- (NSData *)modifyCacheData:(NSData *)cacheData {
    if (!cacheData || [cacheData length] == 0) {
        NSLog(@"Invalid or empty cache data.");
        return cacheData;
    }

    // Convert NSData to a mutable buffer
    NSUInteger size = [cacheData length];
    unsigned char *buffer = malloc(size);
    if (!buffer) {
        NSLog(@"Memory allocation failed.");
        return cacheData;
    }
    [cacheData getBytes:buffer length:size];

    // Call the patch_buffer function
    patch_buffer(buffer, size);

    // Convert the modified buffer back to NSData
    NSData *modifiedData = [NSData dataWithBytes:buffer length:size];

    // Free the buffer
    free(buffer);

    return modifiedData;
}


- (void)modifyPlistAtPath:(NSString *)path {
    // Load plist file
    NSMutableDictionary *plistDict = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
    if (!plistDict) {
        NSLog(@"Failed to load plist at path: %@", path);
        return;
    }

    // Extract CacheData key
    NSData *cacheData = plistDict[@"CacheData"];
    if (!cacheData || ![cacheData isKindOfClass:[NSData class]]) {
        NSLog(@"CacheData key is missing or invalid in plist.");
        return;
    }

    // Modify CacheData
    NSData *modifiedData = [self modifyCacheData:cacheData];

    // Update plist with modified data
    plistDict[@"CacheData"] = modifiedData;

    // Save back to file
    if ([plistDict writeToFile:path atomically:YES]) {
        NSLog(@"Successfully modified and saved plist.");
    } else {
        NSLog(@"Failed to save plist at path: %@", path);
    }
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            NSLog(@"Usage: patcher <path_to_plist>");
            return 1;
        }
        
        NSString *plistPath = [NSString stringWithUTF8String:argv[1]];
        PlistModifier *modifier = [[PlistModifier alloc] init];
        [modifier modifyPlistAtPath:plistPath];
    }
    return 0;
}
